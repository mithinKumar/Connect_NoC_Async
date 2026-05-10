# CONNECT NoC — Codebase Analysis

## What Is This Project?

**CONNECT** (*CONfigurable NEtwork Creation Tool*) is a parameterizable RTL generator for fast, FPGA-friendly Networks-on-Chip (NoCs). It is authored by Michael K. Papamichael at Carnegie Mellon University.

The flow is:
```
Python generator  →  BSV RTL engine  →  Synthesizable Verilog
(gen_network.py)      (.bsv files)         (build/ dir)
```

The workspace at `/home/mithin/Desktop/rnd/connect_new/connect` contains the full engine and supporting files. A second copy at `/home/mithin/Desktop/rnd/connect` holds the hand-edited CDC wrapper files (`NetworkCDC.bsv`, `NetworkCDCTop.bsv`).

---

## Directory Layout

```
connect/
├── gen_network.py              # Python topology & config generator (~2900 lines)
├── inc.v                       # Master Verilog `include — sets all defaults + debug macros
├── sample_mesh_parameters.bsv  # Default 4×4 mesh parameter set (the "seed" config)
├── sample_mesh_links.bsv       # Default 4×4 mesh router connections
│
├── Network.bsv                 # Top-level credit-based NoC module (mkNetwork)
├── NetworkSimple.bsv           # Top-level peek-based NoC module (mkNetworkSimple)
├── NetworkTypes.bsv            # Internal types, Router/Network interfaces
├── NetworkExternalTypes.bsv    # Public types: Flit_t, Credit_t, InPort, OutPort
├── NetworkGlue.bsv             # mkConnectPorts — inter-router link module
├── NetworkGlueSimple.bsv       # Peek-based version of NetworkGlue
├── NetworkIdeal.bsv            # Ideal (zero-latency) network for reference
├── NetworkXbar.bsv             # Crossbar network variant
│
├── Router.bsv                  # mkRouter + mkRouterCore — full VC router
├── RouterSimple.bsv            # mkRouterSimple — peek flow-control router
├── IQRouter.bsv                # Input-queued router variant
├── IQRouterSimple.bsv          # IQ router, peek variant
├── VOQRouterSimple.bsv         # Virtual Output Queued router
│
├── Allocators.bsv              # Separable input/output allocators (IF and OF)
├── Arbiters.bsv                # Round-robin and static priority arbiters
├── MultiFIFOMem.bsv            # Banked multi-VC FIFO memory (BRAM-backed)
├── RegFIFO.bsv                 # Register-based FIFO with count/peek
├── LUTFIFO.bsv                 # LUT-based FIFO
├── DPSRAM.bsv / DPSRAM_w_forward.bsv  # Dual-port SRAM wrappers
│
├── NetworkTb.bsv               # Testbench — credit-based NoC
├── NetworkSimpleTb.bsv         # Testbench — peek-based NoC
├── NetworkTestHarness.bsv      # Shared test harness logic
├── TrafficSource.bsv           # Flit traffic generator for testbenches
├── AllocatorsTb.bsv / RouterTb.bsv  # Unit-level testbenches
│
├── NetworkCDC.bsv              # CDC wrapper (separate repo copy)
├── NetworkCDCTop.bsv           # Synthesizable top with per-PE clocks
│
├── Makefile / makefile.def / makefile.bsc / makefile.syn / makefile.clean
├── inc.v                       # Master include + debug macros
├── Prims/                      # Verilog primitives (SizedFIFO, BRAM, Xbar, etc.)
└── HLS_NoC/                    # Separate HLS-based NoC research artifact (docs only)
```

---

## Layer 1 — Python Generator (`gen_network.py`)

The generator is invoked once to produce three kinds of BSV/hex files for a chosen topology:

| Output file | Purpose |
|---|---|
| `*_parameters.bsv` | `\`define` macros for all router/network parameters |
| `*_links.bsv` | BSV snippet: router instantiations + `mkConnectPorts` calls |
| `*_routing_<id>.hex` | ASCII hex routing table for each router |

### Supported Topologies

`single_switch`, `line`, `ring`, `double_ring`, `star`, `mesh`, `torus`, `fat_tree`, `butterfly`, `uni_tree` (unidirectional), `custom` (user-defined adjacency).

### Key CLI Options

| Flag | Description |
|---|---|
| `-t <topo>` | Topology type |
| `-n <N>` | Number of routers |
| `-v <V>` | VCs per router |
| `-d <D>` | Flit buffer depth |
| `-w <W>` | Flit data width (bits) |
| `--alloc` | Allocator type (`SepIFRoundRobin`, `SepOFRoundRobin`, etc.) |
| `--pipeline_core/allocator/links` | Pipelining toggles |
| `--cdc` / `--cdc_depth` | Generate CDC wrapper top |
| `-o <dir>` | Output directory |

The generator also optionally produces GraphViz `.gv` topology diagrams.

---

## Layer 2 — Parameter/Configuration System

All BSV modules use `\`include "inc.v"` as a universal preamble. `inc.v` does three things:

1. **Selects the configuration file** — defaults to `sample_mesh_parameters.bsv` via:
   ```verilog
   `ifndef NETWORK_PARAMETERS_FILE
     `define NETWORK_PARAMETERS_FILE "sample_mesh_parameters.bsv"
   `endif
   `include `NETWORK_PARAMETERS_FILE
   ```

2. **Sets safe default values** for every parameter if not already defined:
   `NUM_ROUTERS`, `NUM_IN_PORTS`, `NUM_OUT_PORTS`, `NUM_VCS`, `FLIT_BUFFER_DEPTH`, `FLIT_DATA_WIDTH`, `NUM_LINKS`, `ALLOC_TYPE`, `PIPELINE_*`, etc.

3. **Defines debug macros** — `\`DBG(...)`, `\`DBG_ID(...)`, `\`DBG_CYCLES(...)` etc. (compiled out by default; enabled with `\`define EN_DBG`).

The **sample mesh** defaults are: 16 routers (4×4), 5 ports/router, 2 VCs, 8-flit buffer depth, 32-bit data width, `SepIFRoundRobin` allocator.

---

## Layer 3 — BSV Type System (`NetworkExternalTypes.bsv`, `NetworkTypes.bsv`)

### Core Data Types

```
Flit_t {
  Bool           is_tail;      // marks last flit of a packet
  UserRecvPortID_t dst;        // destination port ID
  VC_t           vc;           // virtual channel
  FlitData_t     data;         // user payload
}

Credit_t = Maybe#(VC_t)        // Valid(vc) = credit for that VC; Invalid = no credit

CreditSimple_t = Vector#(NumVCs, Bool)  // bitmask of non-full VCs
```

### Interfaces

**Credit-based** (used in `mkNetwork`):
```
interface InPort  — putFlit(Maybe#(Flit_t))  +  getCredits() → Credit_t
interface OutPort — getFlit() → Maybe#(Flit_t)  +  putCredits(Credit_t)
```

**Peek-based** (used in `mkNetworkSimple`):
```
interface InPortSimple  — putFlit(Maybe#(Flit_t))  +  getNonFullVCs() → Vector#(NumVCs, Bool)
interface OutPortSimple — getFlit() → Maybe#(Flit_t)  +  putNonFullVCs(Vector#(NumVCs, Bool))
```

Both router variants expose `Vector#(NumInPorts, InPort*)` and `Vector#(NumOutPorts, OutPort*)`.

The **Network** interface itself is:
```
interface Network {
  Vector#(NumUserSendPorts, InPort)      send_ports;
  Vector#(NumUserRecvPorts, OutPort)     recv_ports;
  Vector#(NumUserRecvPorts, RecvPortInfo) recv_ports_info;
}
```

---

## Layer 4 — Router Architecture (`Router.bsv`)

### Two-level structure

```
mkRouter(id)          — top-level Router interface
  └─ route table lookup (RegFileMultiport, loaded from *_routing_<id>.hex)
  └─ mkRouterCore()   — actual pipeline logic (synthesizable)
```

### mkRouterCore internals

```
Input side (per in_port × per VC):
  flitBuffers[i]         ← mkInputVCQueues = MultiFIFOMem (BRAM-backed, NumVCs deep)
  outPortFIFOs[i][v]     ← mkOutPortFIFO = RegFIFO (stores destination out_port)

Allocation pipeline:
  eligIO[i][o]           ← Bool matrix: "in_port i has a flit wanting out_port o with credits"
  routerAlloc            ← mkSepRouterAllocator (two-stage separable, see Allocators.bsv)
  selectedIO[i][o]       ← allocation result
  activeIn_perOut[o]     ← which input wins each output

Output side (per out_port):
  hasFlitsToSend_perIn[i] ← DWire carrying the flit selected by gatherFlitsToSend rule
  credits[o][v]           ← counter tracking downstream buffer space

Credit handling:
  credits_set[o][v]      ← DWire: pulsed when credit arrives from downstream
  credits_clear[o][v]    ← DWire: pulsed when flit is sent
  update_credits rule    ← increments/decrements credit counters
```

### Pipelining options (controlled by `\`PIPELINE_CORE`, `\`PIPELINE_ALLOCATOR`, `\`PIPELINE_LINKS`)

When enabled, allocation results are registered across a cycle boundary to improve timing at the cost of latency.

### Optional: Virtual Links (`\`USE_VIRTUAL_LINKS`)
Locks a virtual channel to a specific input port for multi-flit packets, preventing head-of-line blocking for packets in transit.

---

## Layer 5 — Network Assembly (`Network.bsv`, `NetworkGlue.bsv`)

`Network.bsv` (`mkNetworkReal`) does three things at elaborate time:
1. Instantiates `NumRouters` routers: `Vector#(NumRouters, Router) routers <- genWithM(get_rt)`
2. `\`include \`NETWORK_LINKS_FILE` — this BSV snippet (generated by `gen_network.py`) calls `mkConnectPorts` for every inter-router link and assigns `send_ports_ifaces[]` / `recv_ports_ifaces[]`.
3. Exposes the `Network` interface.

`mkConnectPorts` (in `NetworkGlue.bsv`) wires one output port of one router to one input port of another using two rules:
- `makeFlitLink` — calls `getFlit()` on the output, `putFlit()` on the input.
- `makeCreditLink` — calls `getCredits()` on the input, `putCredits()` on the output.

---

## Layer 6 — CDC Wrapper (`NetworkCDC.bsv`, `NetworkCDCTop.bsv`)

> These files live in `/home/mithin/Desktop/rnd/connect/` (older workspace), not in `connect_new`.

### Purpose
Allows each Processing Element (PE) to operate on an **independent clock domain**, while the NoC core runs on its own clock.

### Architecture (`mkNetworkCDCWrapper`)

For each **send port** (PE → NoC):
```
PE clock domain                   NoC clock domain
─────────────────────────────────────────────────────
putFlit()  → flit_in_wire         mkSyncFIFO (flit)  → push_flit_to_noc → noc.send_ports[i].putFlit()
                                  mkSyncFIFO (credit) ← pull_credit_from_noc ← noc.send_ports[i].getCredits()
credit_out_wire ← do_deq_credit ←
getCredits() returns credit_out_wire
```

For each **recv port** (NoC → PE):
```
NoC clock domain                  PE clock domain
─────────────────────────────────────────────────────
noc.recv_ports[i].getFlit() → mkSyncFIFO (flit)  → do_deq_flit → flit_out_wire
                              mkSyncFIFO (credit) ← do_enq_credit ← putCredits()
getFlit() returns flit_out_wire
```

`mkSyncFIFO` is a Bluespec primitive implementing a dual-clock FIFO with two-flip-flop synchronizers. The depth is parameterized (`cdc_depth`, default 4).

### Synthesizable Top (`mkNetworkCDCTop`)

`NetworkCDCTop.bsv` is **generated by `gen_network.py`** when `--cdc` is passed. It flattens the vector clock ports into individual Verilog ports:
```
Clock pe_send_clk_0 .. pe_send_clk_N
Clock pe_recv_clk_0 .. pe_recv_clk_N
Reset pe_send_rst_0 .. (etc.)
```
and calls `mkNetworkCDCWrapper` with those clocks assembled into vectors.

---

## Layer 7 — Allocators & Arbiters (`Allocators.bsv`, `Arbiters.bsv`)

### Allocator variants

| Module | Description |
|---|---|
| `mkSepAllocIF` | Separable Input-First: input arbiters run first, their winners compete at output arbiters |
| `mkSepAllocOF` | Separable Output-First: output arbiters run first, then input arbiters break ties |

Both accept pipelining flags to spread the two stages across clock cycles.

### Arbiter variants

| Module | Description |
|---|---|
| `mkRoundRobinArbiter` | Rotating priority pointer, fairness guaranteed |
| `mkStaticPriorityArbiter` | Fixed priority, lowest index wins |
| `mkRoundRobinArbiterStartAt(i)` | RR starting at a staggered offset to reduce conflicts |

---

## Layer 8 — Memory Primitives (`MultiFIFOMem.bsv`, `Prims/`)

`MultiFIFOMem` is the core buffer for per-VC input queues. It is backed by BRAM primitives from `Prims/` (`BRAM1.v`, `BRAM2.v`), supporting simultaneous enqueue and dequeue across multiple virtual channels with configurable depth.

`Prims/` also contains:
- `SizedFIFO.v` — standard sized FIFO
- `Xbar.v` — crossbar switch primitive
- `RegFile*.v` — multi-port register file variants
- `PipelineFIFO.bsv` — BSV wrapper for pipeline registers
- `testbench_sample.v` / `testbench_sample_peek.v` — Verilog testbench templates

---

## Layer 9 — Build System

### Makefile targets

| Target | Action |
|---|---|
| `<name>-vsim` | Compile BSV → Verilog (BSC verilog backend) |
| `<name>-bsim` | Compile BSV → Bluespec simulation |
| `<name>-xst` | Compile + run Xilinx XST synthesis |
| `<name>-dc` | Compile + run Synopsys DC synthesis |
| `net` | Build `mkNetwork` (credit-based) |
| `net_simple` | Build `mkNetworkSimple` (peek-based) |

### `makefile.def` key functions

- `vsim_compile(top, src)` — invokes `bsc -verilog -g <top> <src>` with the full flag set.
- `xst_compile(top, part)` — copies Verilog to scratch, runs `compile_xst.sh`.
- `copy_vlog` — ensures Prims `.v` files are copied into the `build/` directory before synthesis.

### Key BSC flags

```
-relax-method-earliness   — allows more permissive scheduling
-opt-undetermined-vals    — optimizes don't-care logic
-unspecified-to X         — maps undriven bits to X for simulation
-resource-simple          — simpler resource sharing (faster compile)
+RTS -K3072M -H8192M -RTS — Haskell RTS memory limits (BSC is GHC-based)
```

### Parameter injection at compile time

The Makefile passes `NETWORK_PARAMETERS_FILE` and `NETWORK_LINKS_FILE` as Verilog defines:
```make
USER_FLAGS = -D NETWORK_PARAMETERS_FILE='"path/to/parameters.bsv"' \
             -D NETWORK_LINKS_FILE='"path/to/links.bsv"'
```
This way the same BSV source can be reused for any topology without modification.

---

## Flow Summary

```
1. Run gen_network.py  →  produces parameters.bsv, links.bsv, routing_N.hex
2. make net (or net_simple, NetworkCDCTop-bsc, etc.)
     → BSC compiles Network.bsv + dependencies → build/*.v
3. Synthesize build/*.v with Vivado / XST / DC
4. Integrate mkNetwork (or mkNetworkCDCTop) into your SoC
     — connect send_ports_N and recv_ports_N to your PEs
     — manage credits if using credit-based flow control
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Two flow-control variants (credit vs. peek) | Credits give backpressure over long distances; peek is simpler for FPGA local connections |
| Separable two-stage allocator | Good throughput at much lower area than full matching |
| Route table loaded from hex file | Enables static arbitrary routing with no logic cost |
| BRAM-backed VC queues | FPGA-efficient; enables deep buffers without consuming LUTs |
| `\`include` based config injection | Single RTL source can represent any topology — no per-topology BSV needed |
| CDC via `mkSyncFIFO` | Standard double-flip-flop synchronizer + FIFO; safe for any frequency ratio |
| Generated `NetworkCDCTop.bsv` | Provides a flat Verilog port list (no vector ports) for Vivado compatibility |
