# Conceptual Plan: Implementing an Asynchronous CDC NoC

You want to make the CONNECT NoC operate asynchronously relative to the Processing Elements (PEs). This means the central NoC fabric runs on `clk_noc`, while each PE `i` can run on its own independent `clk_pe_i`.

## 1. The Core Concept: The CDC Wrapper

We will build a **Top-Level CDC Wrapper** that instantiates the existing synchronous `mkNetwork` inside of it. The wrapper will act as a translator, sitting on the border between the `clk_noc` domain and the `clk_pe` domains using Bluespec's `mkSyncFIFO` primitives.

## 2. Python Generator Updates (`gen_network.py`)

As per your instructions, we will make this feature strictly opt-in by modifying the Python generator toolchain.

### New Arguments
We will add two new arguments to `gen_network.py`:
1. **`--cdc`** (Action: `store_true`): A boolean flag. If passed, the generator will output the asynchronous wrapper. If omitted, the standard synchronous NoC is generated.
2. **`--cdc_depth <int>`** (Default: `2`): Specifies the depth of the asynchronous FIFOs at the clock boundary. `2` is the minimum for Gray-code crossing, but it can be increased for higher throughput buffering.

### Code Generation Logic
When the `--cdc` flag is passed, `gen_network.py` will generate two new Bluespec files in the `build/` directory:

1. **`NetworkCDC.bsv` (Static Template)**
   - This file will contain the generic logic for bridging the `Flit` and `Credit` channels using `mkSyncFIFO` primitives.
   - It will define a `mkNetworkCDC` module that wraps `mkNetwork`.

2. **`NetworkCDCTop.bsv` (Dynamically Generated Wrapper)**
   - Because the number of PEs changes dynamically (e.g., 4, 16, 64), we must dynamically generate the absolute top-level module.
   - This file will instantiate `mkNetworkCDC`.
   - **Crucially**, it will dynamically expose the `clk_pe_0`, `clk_pe_1`, etc., and `rst_pe_0`, `rst_pe_1` physical ports to the outside Verilog world, mapping them properly to the internal SyncFIFOs.

## 3. The Port Architecture (Per PE)

### The Send Path (PE $\rightarrow$ NoC)
- **Flit FIFO**: `SyncFIFO` going from `clk_pe` $\rightarrow$ `clk_noc`.
- **Credit FIFO**: `SyncFIFO` going from `clk_noc` $\rightarrow$ `clk_pe`.

### The Receive Path (NoC $\rightarrow$ PE)
- **Flit FIFO**: `SyncFIFO` going from `clk_noc` $\rightarrow$ `clk_pe`.
- **Credit FIFO**: `SyncFIFO` going from `clk_pe` $\rightarrow$ `clk_noc`.

---

## Next Steps
> [!NOTE]
> **Awaiting your command:** I have updated the plan with your arguments. I am holding off on building or editing any code until you give the green light. Once you are ready, I will create a task list and begin editing `gen_network.py` and creating the CDC templates!
