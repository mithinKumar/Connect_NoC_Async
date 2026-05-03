/* =========================================================================
 *
 * Filename:            NetworkCDC.bsv
 * Description:
 * CDC Wrapper for CONNECT NoC to allow PEs to run in independent clocks.
 * 
 * =========================================================================
 */

import Vector::*;
import Clocks::*;
import GetPut::*;

import Network::*;
import NetworkSimple::*;
import NetworkTypes::*;

//===========================================================
// CDC wrapper for Credit-based NoC (mkNetwork)
//===========================================================
module mkNetworkCDCWrapper#(
    Integer cdc_depth,
    Vector#(NumUserSendPorts, Clock) send_clks, 
    Vector#(NumUserSendPorts, Reset) send_rsts, 
    Vector#(NumUserRecvPorts, Clock) recv_clks, 
    Vector#(NumUserRecvPorts, Reset) recv_rsts) (Network);

    Clock noc_clk <- exposeCurrentClock;
    Reset noc_rst <- exposeCurrentReset;

    Network noc <- mkNetwork();

    Vector#(NumUserSendPorts, InPort) send_ports_cdc = newVector();
    Vector#(NumUserRecvPorts, OutPort) recv_ports_cdc = newVector();

    // Send ports processing (PE to NoC)
    for (Integer i = 0; i < valueOf(NumUserSendPorts); i = i + 1) begin
        SyncFIFOIfc#(Maybe#(Flit_t)) flit_sync <- mkSyncFIFO(cdc_depth, send_clks[i], send_rsts[i], noc_clk);
        SyncFIFOIfc#(Credit_t) credit_sync <- mkSyncFIFO(cdc_depth, noc_clk, noc_rst, send_clks[i]);

        Wire#(Maybe#(Flit_t)) flit_in_wire <- mkDWire(Invalid, clocked_by send_clks[i], reset_by send_rsts[i]);
        Wire#(Credit_t) credit_out_wire <- mkDWire(Invalid, clocked_by send_clks[i], reset_by send_rsts[i]);

        rule do_enq_flit (isValid(flit_in_wire) && flit_sync.notFull());
            flit_sync.enq(flit_in_wire);
        endrule

        rule push_flit_to_noc;
            if (flit_sync.notEmpty()) begin
                flit_sync.deq();
                noc.send_ports[i].putFlit(flit_sync.first());
            end else begin
                noc.send_ports[i].putFlit(Invalid);
            end
        endrule
        
        rule pull_credit_from_noc;
            let cr <- noc.send_ports[i].getCredits();
            if (isValid(cr) && credit_sync.notFull()) credit_sync.enq(cr);
        endrule

        rule do_deq_credit (credit_sync.notEmpty());
            credit_sync.deq();
            credit_out_wire <= credit_sync.first();
        endrule
        
        send_ports_cdc[i] = interface InPort;
            method Action putFlit(Maybe#(Flit_t) flit_in);
                flit_in_wire <= flit_in;
            endmethod
            method ActionValue#(Credit_t) getCredits();
                return credit_out_wire;
            endmethod
        endinterface;
    end

    // Recv ports processing (NoC to PE)
    for (Integer i = 0; i < valueOf(NumUserRecvPorts); i = i + 1) begin
        SyncFIFOIfc#(Maybe#(Flit_t)) flit_sync <- mkSyncFIFO(cdc_depth, noc_clk, noc_rst, recv_clks[i]);
        SyncFIFOIfc#(Credit_t) credit_sync <- mkSyncFIFO(cdc_depth, recv_clks[i], recv_rsts[i], noc_clk);

        Wire#(Maybe#(Flit_t)) flit_out_wire <- mkDWire(Invalid, clocked_by recv_clks[i], reset_by recv_rsts[i]);
        Wire#(Credit_t) credit_in_wire <- mkDWire(Invalid, clocked_by recv_clks[i], reset_by recv_rsts[i]);

        rule pull_flit_from_noc;
            let flit <- noc.recv_ports[i].getFlit();
            if (isValid(flit) && flit_sync.notFull()) flit_sync.enq(flit);
        endrule

        rule do_deq_flit (flit_sync.notEmpty());
            flit_sync.deq();
            flit_out_wire <= flit_sync.first();
        endrule

        rule do_enq_credit (isValid(credit_in_wire) && credit_sync.notFull());
            credit_sync.enq(credit_in_wire);
        endrule

        rule push_credit_to_noc;
            if (credit_sync.notEmpty()) begin
                credit_sync.deq();
                noc.recv_ports[i].putCredits(credit_sync.first());
            end else begin
                noc.recv_ports[i].putCredits(Invalid);
            end
        endrule

        recv_ports_cdc[i] = interface OutPort;
            method ActionValue#(Maybe#(Flit_t)) getFlit();
                return flit_out_wire;
            endmethod
            method Action putCredits(Credit_t cr_in);
                credit_in_wire <= cr_in;
            endmethod
        endinterface;
    end

    interface send_ports = send_ports_cdc;
    interface recv_ports = recv_ports_cdc;
    interface recv_ports_info = noc.recv_ports_info;
endmodule

//===========================================================
// CDC Wrapper for Peek-based NoC (mkNetworkSimple)
//===========================================================
module mkNetworkSimpleCDCWrapper#(
    Integer cdc_depth,
    Vector#(NumUserSendPorts, Clock) send_clks, 
    Vector#(NumUserSendPorts, Reset) send_rsts, 
    Vector#(NumUserRecvPorts, Clock) recv_clks, 
    Vector#(NumUserRecvPorts, Reset) recv_rsts) (NetworkSimple);

    Clock noc_clk <- exposeCurrentClock;
    Reset noc_rst <- exposeCurrentReset;

    NetworkSimple noc <- mkNetworkSimple();

    Vector#(NumUserSendPorts, InPortSimple) send_ports_cdc = newVector();
    Vector#(NumUserRecvPorts, OutPortSimple) recv_ports_cdc = newVector();

    // Send ports processing (PE to NoC)
    for (Integer i = 0; i < valueOf(NumUserSendPorts); i = i + 1) begin
        SyncFIFOIfc#(Maybe#(Flit_t)) flit_sync <- mkSyncFIFO(cdc_depth, send_clks[i], send_rsts[i], noc_clk);
        Reg#(Vector#(NumVCs, Bool)) credit_sync <- mkSyncReg(replicate(False), noc_clk, noc_rst, send_clks[i]);

        Wire#(Maybe#(Flit_t)) flit_in_wire <- mkDWire(Invalid, clocked_by send_clks[i], reset_by send_rsts[i]);
        Wire#(Vector#(NumVCs, Bool)) credit_out_wire <- mkDWire(replicate(False), clocked_by send_clks[i], reset_by send_rsts[i]);

        rule do_enq_flit (isValid(flit_in_wire) && flit_sync.notFull());
            flit_sync.enq(flit_in_wire);
        endrule

        rule push_flit_to_noc_send_simple;
            if (flit_sync.notEmpty()) begin
                flit_sync.deq();
                noc.send_ports[i].putFlit(flit_sync.first());
            end else begin
                noc.send_ports[i].putFlit(Invalid);
            end
        endrule
        
        rule pull_credit_from_noc_send_simple;
            let l <- noc.send_ports[i].getNonFullVCs();
            credit_sync <= l;
        endrule

        rule do_read_credit;
            credit_out_wire <= credit_sync;
        endrule
        
        send_ports_cdc[i] = interface InPortSimple;
            method Action putFlit(Maybe#(Flit_t) flit_in);
                flit_in_wire <= flit_in;
            endmethod
            method ActionValue#(Vector#(NumVCs, Bool)) getNonFullVCs();
                return credit_out_wire;
            endmethod
        endinterface;
    end

    // Recv ports processing (NoC to PE)
    for (Integer i = 0; i < valueOf(NumUserRecvPorts); i = i + 1) begin
        SyncFIFOIfc#(Maybe#(Flit_t)) flit_sync <- mkSyncFIFO(cdc_depth, noc_clk, noc_rst, recv_clks[i]);
        Reg#(Vector#(NumVCs, Bool)) credit_sync <- mkSyncReg(replicate(False), recv_clks[i], recv_rsts[i], noc_clk);

        Wire#(Maybe#(Flit_t)) flit_out_wire <- mkDWire(Invalid, clocked_by recv_clks[i], reset_by recv_rsts[i]);
        Wire#(Vector#(NumVCs, Bool)) credit_in_wire <- mkDWire(replicate(False), clocked_by recv_clks[i], reset_by recv_rsts[i]);
        Wire#(Bool) is_credit_in_valid <- mkDWire(False, clocked_by recv_clks[i], reset_by recv_rsts[i]);

        rule pull_flit_from_noc_recv_simple;
            let flit <- noc.recv_ports[i].getFlit();
            if (isValid(flit) && flit_sync.notFull()) flit_sync.enq(flit);
        endrule

        rule do_deq_flit (flit_sync.notEmpty());
            flit_sync.deq();
            flit_out_wire <= flit_sync.first();
        endrule

        rule do_write_credit (is_credit_in_valid);
            credit_sync <= credit_in_wire;
        endrule

        rule push_credit_to_noc_recv_simple;
            noc.recv_ports[i].putNonFullVCs(credit_sync);
        endrule

        recv_ports_cdc[i] = interface OutPortSimple;
            method ActionValue#(Maybe#(Flit_t)) getFlit();
                return flit_out_wire;
            endmethod
            method Action putNonFullVCs(Vector#(NumVCs, Bool) cr_in);
                credit_in_wire <= cr_in;
                is_credit_in_valid <= True;
            endmethod
        endinterface;
    end

    interface send_ports = send_ports_cdc;
    interface recv_ports = recv_ports_cdc;
    interface recv_ports_info = noc.recv_ports_info;

endmodule

//===========================================================
// Dummy Wrappers for Synthesis / Compilation Checking
//===========================================================
(* synthesize *)
module mkNetworkCDCSynth(Network);
    Clock clk <- exposeCurrentClock;
    Reset rst <- exposeCurrentReset;
    Vector#(NumUserSendPorts, Clock) send_clks = replicate(clk);
    Vector#(NumUserSendPorts, Reset) send_rsts = replicate(rst);
    Vector#(NumUserRecvPorts, Clock) recv_clks = replicate(clk);
    Vector#(NumUserRecvPorts, Reset) recv_rsts = replicate(rst);
    
    let _noc <- mkNetworkCDCWrapper(4, send_clks, send_rsts, recv_clks, recv_rsts);
    return _noc;
endmodule

(* synthesize *)
module mkNetworkSimpleCDCSynth(NetworkSimple);
    Clock clk <- exposeCurrentClock;
    Reset rst <- exposeCurrentReset;
    Vector#(NumUserSendPorts, Clock) send_clks = replicate(clk);
    Vector#(NumUserSendPorts, Reset) send_rsts = replicate(rst);
    Vector#(NumUserRecvPorts, Clock) recv_clks = replicate(clk);
    Vector#(NumUserRecvPorts, Reset) recv_rsts = replicate(rst);
    
    let _noc <- mkNetworkSimpleCDCWrapper(4, send_clks, send_rsts, recv_clks, recv_rsts);
    return _noc;
endmodule
