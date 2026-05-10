# CONNECT NoC Codebase Analysis

This document provides a comprehensive overview of the CONNECT (CONfigurable NEtwork Creation Tool) codebase. CONNECT is a highly flexible, FPGA-friendly Network-on-Chip (NoC) generator.

## High-Level Architecture

The system is broken down into two main domains:
1. **Python-based Configuration Generator:** A front-end tool (`gen_network.py`) that interprets user-specified NoC parameters and generates custom configuration and topology files.
2. **Bluespec SystemVerilog (BSV) Hardware Engine:** The core hardware templates that ingest the generated configurations and compile them into synthesizable Verilog modules representing the complete NoC.

> [!NOTE]
> All networks generated through CONNECT consist of fully synthesizable Verilog, optimized for FPGAs.

---

## 1. The Python Generator (`gen_network.py`)

`gen_network.py` is the entry point for generating new NoC architectures. It accepts a wide variety of command-line arguments to customize the NoC's behavior and topology.

### Key Capabilities
- **Topology Generation:** Supports standard topologies like `mesh`, `ring`, `star`, `line`, `torus`, `fat_tree`, `butterfly`, and custom configurations. 
- **Parameter Setup:** Configures the number of routers, data width, virtual channels (VCs), buffer depth, flow control types (credit-based vs peek-based), and allocator types (e.g., Separated Input-First Round Robin).
- **Routing Table Generation:** Calculates optimal routes based on the chosen topology and outputs `.hex` files containing the routing logic for each individual router.

### Outputs
When run, the script creates several files (typically in the `build/` directory):
- `*_links.bsv`: Specifies the physical connections (links) between the routers.
- `*_parameters.bsv`: Specifies the structural parameters of the NoC.
- `*_routing_X.hex`: The pre-calculated routing table for Router X.

---

## 2. Bluespec SystemVerilog Hardware Templates

The `*.bsv` files define the hardware implementation. Bluespec allows for highly parameterized, rule-based hardware generation. 

### Top-Level Network Modules
- **`Network.bsv` (`mkNetwork`)**: The top-level module for networks utilizing **credit-based** flow control. Network clients manage and exchange credits with routers to track buffer availability.
- **`NetworkSimple.bsv` (`mkNetworkSimple`)**: The top-level module for networks utilizing **peek-based** flow control. Clients use a simple interface to check a "non-full" signal before injecting flits.

### Router Implementations
- **`Router.bsv` & `RouterSimple.bsv`**: Virtual Channel (VC) router implementations.
- **`IQRouter.bsv` / `IQRouterSimple.bsv`**: Input-Queued (IQ) router implementations.
- **`VOQRouterSimple.bsv`**: Virtual-Output-Queued router variants.

### Core Primitives & Logic
- **`Allocators.bsv` & `Arbiters.bsv`**: Contain the logic for arbitrating switch allocation and virtual channel allocation. Includes round-robin and matrix allocators.
- **`TrafficSource.bsv` & Testbenches**: Modules for verifying network behavior during simulation.
- **FIFOs and Memories (`MultiFIFOMem.bsv`, `RegFIFO.bsv`, etc.)**: Various buffer implementations tailored for FPGA LUT/BRAM efficiency.

---

## 3. Build System and Flow

The process of taking a NoC configuration to synthesizable Verilog is controlled via the Makefiles (`Makefile`, `makefile.def`, `makefile.syn`, `makefile.bsc`).

### Typical Generation Flow

````mermaid
graph TD
    A[User Command: ./gen_network.py ...] -->|Generates| B(build/ *_links.bsv)
    A -->|Generates| C(build/ *_parameters.bsv)
    A -->|Generates| D(build/ *_routing.hex)
    B --> E[Bluespec Compiler]
    C --> E
    D --> E
    F[Core BSV Templates] --> E
    E -->|make net / make net_simple| G((Synthesizable Verilog .v))
````

### Key Makefile Targets
- `make net`: Compiles the credit-based `mkNetwork.v`.
- `make net_simple`: Compiles the peek-based `mkNetworkSimple.v`.
- The Makefiles also contain targets for running simulations (`%-bsim`, `%-vsim`) and synthesis mappings for specific platforms (XST, DC).

## 4. Interfaces

As detailed in the `README`, the top-level modules expose specific ports for integrating Processing Elements (PEs):
- `send_ports`: Interfaces for endpoints to inject flits into the NoC.
- `recv_ports`: Interfaces for endpoints to extract flits from the NoC.
- Flow Control: Credit lines (for `mkNetwork`) or `getNonFullVCs` / `putNonFullVCs` (for `mkNetworkSimple`).

> [!TIP]
> The repository appears to have a branch or previous state referencing Asynchronous CDC (Clock Domain Crossing) integration. If you are modifying the NoC to support independent PE clocks, you will likely be adding a `NetworkCDCTop.bsv` wrapper that instantiates `mkNetwork` alongside asynchronous FIFOs for the I/O ports.
