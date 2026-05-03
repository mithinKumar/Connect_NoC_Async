import Vector::*;
import Clocks::*;
import Network::*;
import NetworkSimple::*;
import NetworkCDC::*;
import NetworkTypes::*;

(* synthesize *)
module mkNetworkCDCTop(
    Clock pe_send_clk_0, Reset pe_send_rst_0,
    Clock pe_send_clk_1, Reset pe_send_rst_1,
    Clock pe_send_clk_2, Reset pe_send_rst_2,
    Clock pe_send_clk_3, Reset pe_send_rst_3,
    Clock pe_recv_clk_0, Reset pe_recv_rst_0,
    Clock pe_recv_clk_1, Reset pe_recv_rst_1,
    Clock pe_recv_clk_2, Reset pe_recv_rst_2,
    Clock pe_recv_clk_3, Reset pe_recv_rst_3,
    Network ifc);

    Vector#(NumUserSendPorts, Clock) send_clks = newVector();
    Vector#(NumUserSendPorts, Reset) send_rsts = newVector();
    send_clks[0] = pe_send_clk_0;
    send_rsts[0] = pe_send_rst_0;
    send_clks[1] = pe_send_clk_1;
    send_rsts[1] = pe_send_rst_1;
    send_clks[2] = pe_send_clk_2;
    send_rsts[2] = pe_send_rst_2;
    send_clks[3] = pe_send_clk_3;
    send_rsts[3] = pe_send_rst_3;
    Vector#(NumUserRecvPorts, Clock) recv_clks = newVector();
    Vector#(NumUserRecvPorts, Reset) recv_rsts = newVector();
    recv_clks[0] = pe_recv_clk_0;
    recv_rsts[0] = pe_recv_rst_0;
    recv_clks[1] = pe_recv_clk_1;
    recv_rsts[1] = pe_recv_rst_1;
    recv_clks[2] = pe_recv_clk_2;
    recv_rsts[2] = pe_recv_rst_2;
    recv_clks[3] = pe_recv_clk_3;
    recv_rsts[3] = pe_recv_rst_3;
    let _noc <- mkNetworkCDCWrapper(4, send_clks, send_rsts, recv_clks, recv_rsts);
    return _noc;
endmodule
