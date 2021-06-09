`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EF9341 GEN VideoPac 
// Antonio Sánchez (@TheSonders)
// Jun/2021
//
// References:
// https://github.com/mamedev/mame/blob/master/src/devices/video/ef9340_1.cpp
// https://home.kpn.nl/~rene_g7400/vp_info.html
// THOMSON EF9340-EF9341 Datasheet
//////////////////////////////////////////////////////////////////////////////////

// M register bits              Table 3 Page 24
`define M_Access      M[7:5]
`define M_Slice       M[3:0]

// M Access mode                Table 3 Page 24
`define AcMode_WriteMP      3'b000
`define AcMode_ReadMP       3'b001
`define AcMode_WriteMP_NI   3'b010
`define AcMode_ReadMP_NI    3'b011
`define AcMode_WriteSlice   3'b100
`define AcMode_ReadSlice    3'b101
 
module GEN_9341(
    //Added clock input, ideally 14MHz as the VIN
    input wire      clk,
    //CPU interface
    inout wire    [7:0]d,
    input wire         e,
    input wire       _cs,
    input wire       r_w,
    input wire       b_a,
    input wire       c_t,
    //VIN interface
    output reg       _ve=1,
    inout wire  [7:0]busA,
    inout wire  [7:0]busB,
    input wire       r_wi,
    input wire        _sm,
    input wire        _st,
    input wire        _sg,
    input wire   [3:0]adr);
    
assign d=(e & ~_cs & r_w)?(c_t)?{Busy,6'h00}:(b_a)?TB:TA:8'hZZ; //Top of page 13
assign busA=(~_sg & (Gen_Selected || Del_Selected))?OutLatch: //Cycle type 2
            8'hZZ; //Schematics on page 2

wire [7:0]wTC;


//Accesible registers
reg [7:0] TA=0;     //This both are the mailbox
reg [7:0] TB=0;
reg     Busy=0;     //Busy FF
reg [7:0] OutLatch=0;
reg Gen_Selected=0;
reg Del_Selected=0;
reg s=0;
reg i=0;
reg m=0;

//Latchs of previous inputs estates
reg prev_e=1;       //Rise detection of input e
reg prev_sm=0;      //Fall detection of signal from VIN
reg pprev_sm=0;     //Fall detection of signal from VIN
reg prev_sg=0;      //The signal _st may be delayed (tAS on Page 7)...
reg pprev_sg=0;     //Use of double latch to detect delayed _st
reg prev_st=0;      

reg [11:0]CC=0;
reg [7:0]ROM[0:2560];  //<-Character ROM [256 bytes]*[10rows]

initial $readmemh ("charset_ef9341.txt",ROM);

always @(posedge clk)begin
    prev_e<=e;
    prev_sm<=_sm;pprev_sm<=prev_sm;
    prev_sg<=_sg;pprev_sg<=prev_sg;
    prev_st<=_st;
    if (~prev_e & e & ~_cs) begin          //CPU ACCESS
        case ({c_t,b_a,r_w})               //Table on top of page 13
            3'b000:begin TA<=d;end         //Reading accesses are multiplexed on assign
            3'b010:begin TB<=d;Busy<=1;_ve<=0;end
            3'b011:begin Busy<=1;_ve<=0;end//All the accesses on B causes set Busy
            3'b100:begin TA<=d;end
            3'b110:begin TB<=d;Busy<=1;_ve<=0;end
        endcase
    end
    if (pprev_sm & ~prev_sm & ~_sm)begin   //Delayed low pulse on _sm
        if (r_wi) begin
            if (_st)begin                   //Cycle TYPE 1 
                Gen_Selected<=(~busB[7]);
                CC<={busA[7],busB[6:0]}*10;
                if ({busB[7:5],busA[7]}==4'b1000) begin //Delimitor
                    s<=busB[2];
                    i<=busB[1];
                    m<=busB[0];
                    Del_Selected<=1;
                end
                else Del_Selected<=0;
            end
            else begin                      //Cycle TYPE 4
                TA<=busA;
                TB<=BusB;
                prev_st<=0; //Ignore fall on _st
            end
        end
    end
end    

endmodule
