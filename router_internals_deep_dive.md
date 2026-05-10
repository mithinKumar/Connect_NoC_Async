# The Router Internals: A Step-by-Step Deep Dive

Let’s strip away the code and look at the physical hardware of a single router. Imagine a physical silicon chip on your desk. 

## 1. The Physical Interface (Ports)

In a standard Mesh Network (like the 4x4 mesh you generated), almost every router has **5 physical ports**:
1. **North**
2. **South**
3. **East**
4. **West**
5. **Local** (This connects to your custom Processing Element/CPU)

Each "Port" is actually a pair of one-way streets. For example, the East Port has:
* An **Input Bus** (receiving data from the router to the East).
* An **Output Bus** (sending data to the router to the East).

## 2. What is traveling on the wires? (Flits & VCs)

#### The Flit
A packet of data is too big to fit on the 32-bit output bus all at once. So, we chop the packet into **Flits** (Flow control units). 
A Flit is a struct of physical wires containing:
* `Valid Bit` (Is there data here?)
* `Destination ID` (Where am I going?)
* `Tail Bit` (Am I the very last piece of the packet?)
* `32 bits of Payload Data`

#### The Virtual Channel (VC)
Imagine a physical wire connecting Router 0 to Router 1. If Packet A is moving slowly across that wire, Packet B gets stuck behind it.
To fix this, we put **multiple buffers (waiting rooms)** at the input port of a router. If your network has `2 VCs`, it means the West Input Port has two separate waiting rooms: VC0 and VC1. 
If Packet A gets stuck in VC0, the router can just pause it, and let Packet B travel across the physical wire and go into VC1. We are multiplexing multiple streams of traffic over one physical wire.

---

## 3. The Internal Flow (The 4-Stage Pipeline)

Let's follow a single Flit as it travels through the router. 

Imagine a Flit arrives from the **West Input Port**, and its destination says it needs to go out the **East Output Port**.

### Stage 1: Buffer Write (BW)
The Flit enters the router from the West wire. The router sees that this Flit is tagged as `VC0`. The router immediately dumps the Flit into the West Port's `VC0` buffer (which is implemented in `RegFIFO.bsv` or `MultiFIFOMem.bsv`). The Flit sits in this buffer and waits.

### Stage 2: Route Computation (RC)
The router looks at the Flit sitting at the front of the West `VC0` buffer. It reads the `Destination ID` on the Flit. It looks at the `.hex` routing tables you generated and computes: 
> *"Okay, to get to this destination, this Flit needs to leave out of my East Output Port."*

### Stage 3: Allocation and Arbitration (The Traffic Cops)
This is the most complicated part. The Flit knows where it wants to go, but it needs permission to move. It needs two types of permission:

**Step 3a: Virtual Channel Allocation (VA)**
The Flit wants to leave via the East port, which means it will enter the *next* router down the line. But what if the *next* router's buffers are full? 
The VC Allocator looks at the next router and asks: *"Do you have an empty VC buffer for my Flit?"* If the next router says yes, the Flit is granted a VC.

**Step 3b: Switch Allocation (SA) & Arbitration**
Now the Flit has a destination and a reserved parking spot at the next router. But what if a completely different Flit from the **North Input Port** *also* wants to leave via the **East Output Port** on the exact same clock cycle? 
They crash into each other. Only one can use the physical East wire per clock cycle.

This is where **Arbiters** (`Arbiters.bsv`) and **Allocators** (`Allocators.bsv`) come in. 
An Arbiter is just a hardware coin-flipper. Usually, it uses "Round-Robin". 
* The Switch Allocator (SA) says: *"West Port and North Port both want the East Output wire. Last time, I let West go. So this time, I grant permission to the North Port."*
* Our Flit from the West Port is denied. It has to sit in its buffer and wait for the next clock cycle.
* On the next clock cycle, the Allocator finally grants permission to our West Port Flit.

### Stage 4: Switch Traversal (The Crossbar)
Now our Flit finally has the green light.
Inside the router is a **Crossbar Switch** (`NetworkXbar.bsv`). Think of a crossbar like an old-school telephone operator switchboard. It is a giant web of multiplexers that can physically connect any input port to any output port.

Because the Switch Allocator gave permission, the Crossbar physically rotates its internal hardware switches to directly connect the wires from the **West VC0 Buffer** to the **East Output Port**. 

The Flit drives across the crossbar, exits the router, and travels down the physical wire towards the next router.

---

### Summary of the Blocks
If you look at the `mkRouterCore` in the code, you will see exactly these blocks instantiated:
1. `mkInputVCQueues` (The waiting rooms / Stage 1)
2. `mkRouteTableSynth` (The map / Stage 2)
3. `mkVCAllocator` & `mkSwitchAllocator` (The traffic cops / Stage 3)
4. `mkNetworkXbar` (The physical switchboard / Stage 4)
