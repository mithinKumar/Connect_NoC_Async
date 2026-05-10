# CONNECT NoC: The Complete `.bsv` File Encyclopedia

This document catalogs every single Bluespec SystemVerilog (`.bsv`) file in the repository, grouped by their architectural role in the NoC.

---

## 1. Top-Level Network Containers
These files act as the giant wrappers that instantiate the array of routers and wire them together.

* **`Network.bsv`**: The absolute top-level module (`mkNetwork`). It implements a **credit-based** flow control NoC. It exposes `send_ports` and `recv_ports` with credit handshaking for your Processing Elements.
* **`NetworkSimple.bsv`**: An alternative top-level module (`mkNetworkSimple`). It implements a **peek-based** flow control NoC. Instead of credit counters, PEs just check a "not full" bitmask to see if they can send.
* **`NetworkIdeal.bsv`**: A "perfect" simulated network (`mkNetworkIdeal`). Flits instantly reach their destination with 0 routing delay. It's used purely as a baseline for performance comparisons during simulation, not for physical hardware.

---

## 2. Router Core Microarchitectures
These files define the internal "brain" and pipeline of the routers.

* **`Router.bsv`**: The standard, full-featured **Virtual Channel (VC)** router. Uses credit-based flow control. It implements the 4-stage pipeline: Buffer Write, Route Compute, VC/Switch Allocation, and Switch Traversal.
* **`RouterSimple.bsv`**: Identical in microarchitecture to `Router.bsv`, but designed to interface with the peek-based `NetworkSimple.bsv` wrapper.
* **`IQRouter.bsv`**: An **Input-Queued (IQ)** router. It strips out the concept of Virtual Channels entirely to save hardware area and reduce complexity, though it is vulnerable to Head-of-Line blocking.
* **`IQRouterSimple.bsv`**: The peek-based version of the Input-Queued router.
* **`VOQRouterSimple.bsv`**: A **Virtual Output Queued (VOQ)** router (peek-based). A compromise architecture: it doesn't use true VCs across wires, but it segregates input buffers based on their *destination output port* to prevent Head-of-Line blocking.

---

## 3. Allocation and Arbitration
These files resolve traffic jams when multiple flits want the same resource.

* **`Arbiters.bsv`**: Contains primitive 1-dimensional "traffic cops". For example, `mkRoundRobinArbiter` and `mkMatrixArbiter`. If 5 signals want access to 1 wire, the Arbiter picks the 1 winner fairly.
* **`Allocators.bsv`**: Contains complex 2-dimensional scheduling logic built out of arrays of Arbiters. Used heavily by `Router.bsv`.
  * *VC Allocators*: Matches an Input VC to an empty Output VC on the next router.
  * *Switch Allocators*: (e.g., `mkSepIFRoundRobinAllocator`). Matches winning Input Ports to available physical Output Ports so they can cross the switch.

---

## 4. The Crossbar Switch
* **`NetworkXbar.bsv`**: The physical multiplexer logic (`mkNetworkXbar`). Once the Allocator decides *who* gets to move, this module physically wires the 32-bit (or 64-bit) data paths from the input buffers to the output ports.

---

## 5. Buffers, FIFOs, and Memory
Hardware arrays used to hold flits while they wait to be routed. Bluespec selects the best one based on your chosen Flit Buffer Depth and FPGA target.

* **`RegFIFO.bsv`**: A standard queue built entirely out of discrete logic registers (Flip-Flops). Extremely fast but consumes a lot of FPGA logic area. Good for very small buffers (depth 2 or 4).
* **`LUTFIFO.bsv`**: A queue optimized to synthesize down into FPGA Look-Up Tables (LUTRAM/Distributed RAM). 
* **`MultiFIFOMem.bsv`**: A highly optimized module that packs multiple Virtual Channel queues into a single physical memory block, saving massive amounts of area.
* **`DPSRAM.bsv` & `DPSRAM_w_forward.bsv`**: Dual-Ported Static RAM primitives. Used under the hood by `MultiFIFOMem` to allow simultaneous reading and writing.
* **`FIFOCountDeqBus.bsv`**: A specialized FIFO wrapper that exposes a counter of how many elements are currently inside it (used for tracking credits).

---

## 6. Types, Includes, and Glue Logic
The "connective tissue" of the codebase.

* **`NetworkTypes.bsv`**: **CRITICAL FILE.** Defines the `struct` for a `Flit` (valid bit, destination address, VC id, and payload data). Defines the `Credit` structs. Contains typedefs for `RouterID`, `PortID`, etc.
* **`NetworkExternalTypes.bsv`**: Similar to `NetworkTypes`, but specifies the types exposed directly to the user's Processing Elements on the boundary of the NoC.
* **`NetworkGlue.bsv` & `NetworkGlueSimple.bsv`**: These files ingest the Python-generated `_links.bsv` and `_parameters.bsv` logic and physically "glue" them to the instantiated routers to create the final netlist.

---

## 7. Primitives & Aux Logic
* **`Aux.bsv`**: Contains helper functions, math macros, and small utility modules used throughout the project.
* **`Count.bsv`**: A simple hardware counter module.
* **`GenReg.bsv`**: A generic register primitive used for pipelining signals.
* **`RF_1port.bsv`, `RF_16ports.bsv`, `RF_16portsLoad.bsv`**: Register File primitives. Used by the allocators to maintain state (like Round-Robin pointers) across clock cycles.
* **`Strace.bsv`**: Simulation trace utilities. Generates text logs during Bluesim/ModelSim simulation to track flit movement.

---

## 8. Testbenches and Simulation
Files ending in `Tb` or related to traffic generation. They do not synthesize into the final NoC; they are only used for simulation testing.

* **`TrafficSource.bsv`**: A synthetic hardware module (`mkTrafficSource`) that generates random or patterned flits and pumps them into the NoC to test it.
* **`NetworkTb.bsv` / `NetworkSimpleTb.bsv`**: The main testbenches for the entire NoC. Instantiates the network, attaches `TrafficSource` modules to every port, runs the simulation, and measures latency/throughput.
* **`NetworkTestHarness.bsv`**: A wrapper that sets up the testbench environment.
* **`RouterTb.bsv`**: A unit test specifically designed to inject flits into a single isolated router.
* **`AllocatorsTb.bsv`**: A unit test to verify that the complex matching algorithms in `Allocators.bsv` don't deadlock or drop requests.
