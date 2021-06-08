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
// R register bits
`define R_Display     R[0]
`define R_Boxing      R[1]
`define R_Conceal     R[2]
`define R_Service     R[3]
`define R_Cursor      R[4]
`define R_Monitor     R[5]
`define R_50Hz        R[6]
`define R_Blinking    R[7]

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

//AttrL from Page Memory    Table 1 Page 23
`define ATR_RED             AttrL[0]
`define ATR_GREEN           AttrL[1]
`define ATR_BLUE            AttrL[2]
`define ATR_STABLE          AttrL[3]
`define ATR_DHEIGHT         AttrL[4]
`define ATR_DWIDTH          AttrL[5]
`define ATR_REVERSE         AttrL[6]

//TypeL from Page Memory         Table 1 Page 23
`define DELIMITER           (TypeL==4'b1000)                        
`define ALPHANUMERIC        (~TypeL[0])
`define ILLEGAL             (TypeL==4'b1001)        
//`define SEMIGRAPHIC         

//Command codes from busB[7:5] Page 13
`define COM_BeginRow    3'b000
`define COM_LoadY       3'b001
`define COM_LoadX       3'b010
`define COM_IncC        3'b011
`define COM_LoadM       3'b100
`define COM_LoadR       3'b101
`define COM_LoadY0      3'b110

//Attribute bits for ATTR
`define ATTR_STABLE          ATTR[0]
`define ATTR_DHEIGHT         ATTR[1]
`define ATTR_DWIDTH          ATTR[2]
`define ATTR_REVERSE         ATTR[3]

//Others
`define Service_Row         31
`define syt_Sample_Window   11

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
    
assign d=(e & ~_cs & r_w)?(c_t)?{Busy,6'h00}:(b_a)?B:A:8'hZZ; //Top of page 13

reg [7:0] A=0;
reg [7:0] B=0;
reg     Busy=0;
    
always @(posedge e) begin
    if (~_cs) begin
        if (~r_w)begin      //Top of page 13
            if (b_a) B<=d;
            else A<=d;
        end
        if (b_a)begin Busy<=1;ve<=0;end
    end
end



endmodule
