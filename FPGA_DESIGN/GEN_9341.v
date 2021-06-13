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

module GEN_9341(
    //Added clock input, ideally 14MHz as the VIN
    input wire      clk,
    //CPU interface
    inout wire    [7:0]d,
    input wire         e,
    input wire      cs_n,
    input wire       r_w,
    input wire       b_a,
    input wire       c_t,
    //VIN interface
    output wire      ve_n,
    inout wire  [7:0]busA,
    inout wire  [7:0]busB,
    input wire       r_wi,
    input wire       sm_n,
    input wire       st_n,
    input wire       sg_n,
    input wire   [3:0]adr);
    
assign d=(e & ~cs_n & r_w)?(c_t)?{Busy,6'h00}:(b_a)?TB:TA:8'hZZ; //Top of page 13
assign busA=(r_wi & ~sg_n & (Gen_Selected || Del_Selected))?OutA: //Cycle TYPE 2,6
            (~r_wi & ~st_n)? TA:                          //Cycle TYPE 3,5,7
            8'hZZ; //Schematics on page 2
assign busB=(~r_wi & ~st_n)? TB:                          //Cycle TYPE 3,5,7
            8'hZZ;
assign ve_n=~Busy;

//Accesible registers
reg [7:0] TA=0;     //This both are the mailbox
reg [7:0] TB=0;
reg     Busy=0;     //Busy FF
reg [7:0] OutA=0;
reg Gen_Selected=0;
reg Del_Selected=0;
reg s=0;
reg i=0;
reg m=0;

//Latchs of previous inputs
reg prev_e=1;       //Rise detection of input e
reg prev_sm=0;      //Fall detection of signal from VIN
reg prev_sg=0;      
reg pprev_sm=0;     //The signal st_n may be delayed (tAS on Page 7)...
reg pprev_sg=0;     //Use of double latch to detect delayed st_n     
reg prev_st=0;
reg pprev_st=0;

reg [11:0]CC=0;
reg [7:0]ROM[0:2560];  //<-Character ROM [256 bytes]*[10rows]

initial $readmemh ("charset_ef9341.txt",ROM);

always @(posedge clk)begin
    prev_e<=e;
    prev_sm<=sm_n;pprev_sm<=prev_sm;
    prev_sg<=sg_n;pprev_sg<=prev_sg;
    prev_st<=st_n;pprev_st<=prev_st;
    //CPU ACCESS
    if (~prev_e & e & ~cs_n) begin          
        case ({c_t,b_a,r_w})               //Table on top of page 13
            3'b000:begin TA<=d;end         //Reading accesses are multiplexed on assign
            3'b010:begin TB<=d;Busy<=1;end
            3'b011:begin Busy<=1;end//All the accesses on B causes set Busy
            3'b100:begin TA<=d;end
            3'b110:begin TB<=d;Busy<=1;end
        endcase
    end
    //INTERNAL BUS ACCESS
    if (pprev_sm & ~prev_sm & ~sm_n)begin   //Delayed low pulse on sm_n
        if (r_wi) begin
            if (st_n)begin                   //Cycle TYPE 1 
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
                TB<=busB;
            end
        end
    end
    else if (pprev_sg & ~prev_sg & ~sg_n)begin   //Delayed low pulse on sg_n
        if (r_wi) begin
            if (st_n)begin                   //Cycle TYPE 2 
                if (Gen_Selected) OutA<=ROM[CC+adr];
                else if (Del_Selected) OutA<={5'h00,s,i,m};
            end
            else begin                      //Cycle TYPE 6
                TA<=busA;
                TB<=busB;
            end
        end
    end
    else if (pprev_st & ~prev_st & ~st_n & ~r_w) Busy<=0; //Cycle TYPE 3
end   
endmodule
