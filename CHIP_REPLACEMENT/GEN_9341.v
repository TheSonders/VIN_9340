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

reg [7:0] TA=0;
reg [7:0] TB=0;
reg     Busy=0;
reg [7:0] OutLatch=0;
reg Gen_Selected=0;
reg Del_Selected=0;
reg s=0;
reg i=0;
reg m=0;
reg [11:0]CC=0;
reg [7:0]ROM[0:2560];  //<-Character ROM [256 bytes]*[10rows]

initial $readmemh ("charset_ef9341.txt",ROM);
    
always @(posedge e) begin
    if (~_cs) begin
        if (~r_w)begin      //Top of page 13
            if (b_a) TB<=d;
            else TA<=d;
        end
        if (b_a)begin Busy<=1;_ve<=0;end
    end
end

always @(posedge _sm) begin //Figure 5 page 6 
    if (r_wi) begin     //Cycle Type 1 
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
    
end

always @(negedge _sg) begin //Figure 5 page 6 
    if (r_wi) begin     //Cycle Type 2
        if (Gen_Selected) OutLatch<=ROM[CC+adr];
        else if (Del_Selected) OutLatch<={5'h00,s,i,m};
    end
end

endmodule
