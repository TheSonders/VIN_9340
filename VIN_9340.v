`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EF9340 VIN VideoPac 
// Antonio Sánchez (@TheSonders)
// May/2021
// https://github.com/mamedev/mame/blob/master/src/devices/video/ef9340_1.cpp
// https://home.kpn.nl/~rene_g7400/vp_info.html
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
`define AcMode_Write        3'b000
`define AcMode_Read         3'b001
`define AcMode_WriteNI      3'b010
`define AcMode_ReadNI       3'b011
`define AcMode_WriteSlice   3'b100
`define AcMode_ReadSlice    3'b101

//Command codes from busB[7:5] Page 13
`define COM_BeginRow    3'b000
`define COM_LoadY       3'b001
`define COM_LoadX       3'b010
`define COM_IncC        3'b011
`define COM_LoadM       3'b100
`define COM_LoadR       3'b101
`define COM_LoadY0      3'b110

module VIN_9340(
    //Bus interface
    input wire  [7:0]busA,
    input wire  [7:0]busB,  //[4:0]not used
    output reg  [9:0]adr=0,
    output reg  r_w=1,
    output reg  _sm=1,      //Page memory strobe
    output reg  _sg=1,      //Char gen strobe
    output reg  _st=1,      //Mailbox strobe
    //Video interface
    output wire r,g,b,      //Color signal
    output wire tt,         //Vertical sync
    output wire tl,         //horizontal sync
    output wire i,          //Insert into extern video
    input wire  syt,        //Vertical sync input
    //Others
    input wire  clk,        //3.5MHz
    input wire  _ve,        //Vin Select (activated by GEN if command)
    input wire  c_t,        //Command/data (high by GEN if command)
    input wire  _res        //Restart
    );

////////////////////////////////////////////////////////
//Timing generator
//Divides by 4 the input clock, it calls window timing (875KHz)
//Then divides by 56 to get de HSync TL(15'625KHz)
//This frec is divided by 262 or 312 to get VSync TT(Interpolate fields)
//This line counter can be reset by a high to low on SYT (sampled at 12th window)
////////////////////////////////////////////////////////
//Display automaton
//Controls bus during 40 windows/line and 210 or 250 lines/field
//Two read cycles for visible window period:
//First: puts the window counter on the 10 bits bus address
//       gets 11 bits, 7 for the attribute plus 4 for the char type
//       increments window counter
//Second:puts on the address bus the number of slice (0 to 9)
//       gets the 8 bits dots for the current line
//       flush the RGBI signals for each dot
////////////////////////////////////////////////////////
//Access automaton
//This automaton access the bus while is not used by the Display Auto.
//Uses the signal C/_T to find out if there's a command or transfer pending
//Reads TA and TB registers from the GEN (mailbox)


//Horizontal sync wire
assign tl=(`R_Monitor)?(TF<12 || TF>51)?1:0:  //16 pulses high, remains low
          (TF<4)?0:1;                       //4 pulses low, remains high    
//Vertical sync wire
assign tt=(LineCounter>1);
//Bus allow for the display automaton
wire VisibleLine=(TF>11) && (TF<52);
wire BusEnable=(`R_Display)?
    (`R_50Hz && LineCounter>38 && LineCounter<290)?VisibleLine:
    (~`R_50Hz && LineCounter>30 && LineCounter<242)?VisibleLine:0:0;
//Coded address of the X/Y positions
wire [9:0]Transcode=(Y[4] & Y[3])?
        {2'b11,X[5:3],2'b11,X[2:0]}:
        (X[5])?{2'b11,Y[2:0],Y[4:3],X[2:0]}:
        {Y[4:0],X[4:0]};
        
reg [7:0] R=1;      //<---------------DEBUG
reg [7:0] M=0;
reg [5:0] X=0;
reg [4:0] Y=0;
reg [5:0] Y0=0;
reg [6:0] Attribute_Latch=0;    //Page 17
reg [3:0] Type_Latch=0;
reg [3:0] SliceNumber=0;
reg [7:0] SliceVal=0;


reg [1:0]WindowDivider=0;       //0 to 3
reg [5:0]TF=0;                  //0 to 55 Total Windows per line
reg [8:0]LineCounter=0;         //0 to 261 or 311
reg c_t_copy=0;
reg _ve_copy=0;

always @(posedge clk)begin
    WindowDivider<=WindowDivider+1;       
    if (BusEnable) begin            //STATE MACHINE FOR THE 
                                    //DISPLAY AUTOMATON (Page 3)
        case (WindowDivider)        //Figure 5 / Page 6
            {2'b00}:begin           //CYCLE TYPE 1 (Page 19)
                adr<=Transcode;
                r_w<=1;
                _sm<=0;
                INC_C;
                end
            {2'b01}:begin           //Page memory detects _sm
                _sm<=1;             //at this point
                Attribute_Latch<=busA[6:0];
                Type_Latch<={busA[7],busB[7:5]};
                end             
            {2'b10}:begin           //CYCLE TYPE 2 (Page 19)       
                adr[3:0]<=SliceNumber;
                _sg<=0;
                end
            {2'b11}:begin           //GEN detects _sg
                _sg<=1;             //at this point
                SliceVal<=busA[7:0];
                end
        endcase
    end     //BusEnable==HIGH
    
    else begin                          //STATE MACHINE FOR THE 
                                        //ACCESS AUTOMATON (Page 3 Column 2)
        case (WindowDivider)            //Figure 7 / Page 7
            {2'b00}:begin
                if (~_ve) begin         //Access pending
                    c_t_copy<=c_t;      //Reading will reset the busy FF
                    _ve_copy<=_ve;      //Capture a copy of C/T and _VE
                    if (c_t) begin      //CYCLE TYPE 3 (Page 19)
                        _st<=0;
                        r_w<=0;
                    end
                end
                end
            {2'b01}:begin           //WAIT
                end             
            {2'b10}:begin       
                if (c_t_copy) begin
                    DECODE_COMMAND;
                end
                end
            {2'b11}:begin       
                _sg<=1;         
                SliceVal<=busA[7:0];
                end
        endcase
    end     //BusEnable==LOW
        
    if (&WindowDivider)begin 
        if (TF==55)begin
            TF<=0;
            if ((~`R_50Hz && LineCounter==261)
                ||LineCounter==311)
                LineCounter<=0;
            else LineCounter<=LineCounter+1;
        end
        else TF<=TF+1;
    end //WindowDivider
end

task INC_C;             //STATE DIAGRAM on PAGE 14
begin
    if (X==39 || X==47 || X==55 || X==63) begin
        X=0;
        if (Y==23) Y=0;
        else Y=Y+1;
    end
    else begin
        X=X+1;    
        Y=Y;
    end
end
endtask

task DECODE_COMMAND;      //Table 2 page 24
begin
    case (busB[7:5])
    `COM_BeginRow:  begin X=0;Y=busA[4:0];end
    `COM_LoadY:     begin Y=busA[4:0];end
    `COM_LoadX:     begin X=busA[5:0];end
    `COM_IncC:      begin INC_C;end
    `COM_LoadM:     begin M=busA;end
    `COM_LoadR:     begin R=busA;end
    `COM_LoadY0:    begin Y0=busA[5:0];end
    endcase
end
endtask

endmodule
