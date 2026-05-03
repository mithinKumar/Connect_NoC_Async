import Clocks::*;
import Vector::*;

interface TestIfc;
    (* always_ready *) method ActionValue#(Bool) getVal();
    (* always_ready *) method Action putVal(Bool in);
endinterface

module mkTestSync(TestIfc);
    Clock clk <- exposeCurrentClock;
    Reset rst <- exposeCurrentReset;
    SyncFIFOIfc#(Bool) syncFIFO <- mkSyncFIFO(4, clk, rst, clk);

    Wire#(Bool) out_wire <- mkDWire(False);
    Wire#(Bool) in_wire <- mkDWire(False);
    Wire#(Bool) in_valid <- mkDWire(False);

    rule do_deq_getVal (syncFIFO.notEmpty);
        syncFIFO.deq();
        out_wire <= syncFIFO.first();
    endrule

    rule do_enq_putVal (in_valid && syncFIFO.notFull);
        syncFIFO.enq(in_wire);
    endrule

    method ActionValue#(Bool) getVal();
        return out_wire;
    endmethod

    method Action putVal(Bool in);
        in_wire <= in;
        in_valid <= True;
    endmethod
endmodule
