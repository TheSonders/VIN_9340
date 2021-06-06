`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EF9340 VIN VideoPac 
// Antonio Sánchez (@TheSonders)
// May/2021
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

`define Service_Row     31  

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
//Coded address of the C Cursor positions
wire [9:0]Transcode_C=(YC[4] & YC[3])?
        {2'b11,XC[5:3],2'b11,XC[2:0]}:
        (XC[5])?{2'b11,YC[2:0],YC[4:3],XC[2:0]}:
        {YC[4:0],XC[4:0]};
        
//Accesible registers (Page 25)
reg [7:0] R=8'h41;      // Display and timing Register <------DEBUG
reg [7:0] M=0;          // Access Mode Register
//These both regs shape the Cursor C Register
reg [5:0] XC=0;         // Horizontal Cursor Pos
reg [4:0] YC=0;         // Vertical Cursor Pos
reg [5:0] Y0=0;         // Origin Row + Zoom mode

//Internal Counters
reg [5:0] X=0;          // Horizontal Window Counter
reg [4:0] Y=0;          // Vertical Window Counter
reg [3:0] S=0;          // Slice Counter
reg [5:0]BlinkCounter=0; //Frame counter to get about 0.5Hz
`define BLINK_ACTIVE BlinkCounter[5]
reg [1:0]WindowDivider=0;       //0 to 3
reg [5:0]TF=0;                  //0 to 55 Total Windows per line
reg [8:0]LineCounter=0;         //0 to 261 or 311

//Internal Latches
reg [6:0] AttrL=0;      //Page 17
reg [3:0] TypeL=0;
reg [7:0] SliceVal=0;   // Bitmap Shift register 
reg [2:0] C0=0;         //BGR Color for background
reg [2:0] C1=0;         //BGR Color for foreground
reg [3:0] ATTR=0;       //Attributes for custom char
reg BOXED=0;
reg CONCEALED=0;
reg UNDERLINE=0;
reg ZOOM=0;
reg c_t_copy=0;
reg _ve_copy=1;
reg HParity=0;          //Double Height order(Page 20)
reg WParity=0;          //Double Width order
reg DHeight=0;          //Double Height found in this Row
reg DWidth=0;           //Double Width found in this Column

//Register for color flush over DDR
reg [2:0]BGR_HIGH=0;
reg [2:0]BGR_LOW=0;

always @(posedge clk)begin
    WindowDivider<=WindowDivider+1;

///////////////////////////////////////////////
//BUS ACCESS FOR THE DISPLAY AUTOMATON (Page 3)
///////////////////////////////////////////////
    if (BusEnable) begin            
                                    
        case (WindowDivider)        //Figure 5 / Page 6
            {2'b00}:begin           //CYCLE TYPE 1 (Page 19)
                adr<=Transcode;
                r_w<=1;
                _sm<=0;
                INC_X;
                end
            {2'b01}:begin           //Page memory detects _sm
                _sm<=1;             //at this point
                AttrL<=busA[6:0];
                TypeL<={busB[7:5],busA[7]};
                end             
            {2'b10}:begin           //CYCLE TYPE 2 (Page 19) 
                if (`ALPHANUMERIC && `ATR_DHEIGHT) begin
                end
                else adr[3:0]<=S;        //Check if GEN or EXTENSION
                adr[4]<=TypeL[3] & (TypeL[2] | TypeL[1]); //NOTA in page 19
                _sg<=0;
                end
            {2'b11}:begin           //GEN detects _sg
                _sg<=1;             //at this point
                DECODE_WINDOW_CODE;
                end
        endcase
    end     //BusEnable==HIGH

///////////////////////////////////////////////
//BUS ACCESS FOR THE ACCESS AUTOMATON (Page 3 Column 2)
///////////////////////////////////////////////
    else begin                          
        case (WindowDivider)            //Figure 7 / Page 7
            {2'b00}:begin
                if (~_ve) begin         //Access pending?
                    c_t_copy<=c_t;      //Reading will reset the busy FF
                    _ve_copy<=_ve;      //Capture a copy of C/T and _VE
                    if (c_t) begin      //CYCLE TYPE 3 (Page 19)
                        _st<=0;
                        r_w<=0;
                    end
                    else ACCESS_MODE;
                end
                end
            {2'b01}:begin               //WAIT
                end             
            {2'b10}:begin
                if (~_ve_copy) begin
                    if (c_t_copy) begin
                        DECODE_COMMAND;
                    end
                    else begin
                        if (`M_Access==`AcMode_WriteMP ||
                            `M_Access==`AcMode_ReadMP)INC_C;
                    end
                end
                end
            {2'b11}:begin               //RESTORE BUS AND COPY     
                    _ve_copy<=1;
                    _st<=1;
                    _sm<=1;
                    _sg<=1;
                end
        endcase
    end     //BusEnable==LOW

///////////////////////////////////////////////
//FRAME TIMING (Page 18)
///////////////////////////////////////////////        
    if (&WindowDivider)begin 
        if (TF==55)begin
            TF<=0;
            DWidth<=0;
            X<=0;
            BOXED<=0;
            CONCEALED<=0;
            UNDERLINE<=0;
            C0<=0;         //X COLUMN 0 RESETS SOME ATTRIBUTES (Top of Page 20)
            if ((~`R_50Hz && LineCounter==261)  //New Frame
                ||LineCounter==311) begin
                LineCounter<=0;
                BlinkCounter<=BlinkCounter+1;
                end
            else begin 
                LineCounter<=LineCounter+1;     //New Screen Line
                if ((`R_50Hz && LineCounter==38) || (~`R_50Hz && LineCounter==30)) begin
                    Y<=`Service_Row;            //Service Row
                    HParity<=0;                 //Restore double settings
                    DHeight<=0; 
                    S<=0;
                end
                else begin                    //Slice & Y increment
                    if (~ZOOM || LineCounter[0] || Y==`Service_Row) INC_S;    
                end
            end
        end
        else begin
            DWidth<=0;
            TF<=TF+1;
        end 
    end //WindowDivider

///////////////////////////////////////////////
//COLOR FLUSH
///////////////////////////////////////////////        
///////////////////////////////////////////////
//FOR A DDR OUTPUT OR CHIP REPLACEMENT.
//REPLACE FOR AN INTEGRATED FPGA DESIGN OR PLL DOUBLING CLOCK
///////////////////////////////////////////////        
    if (BusEnable) begin
        SliceVal<={SliceVal[5:0],2'b00};
        BGR_HIGH<=SliceVal[7]?C1:C0;
        BGR_LOW<=SliceVal[6]?C1:C0;
    end
    else begin
        BGR_HIGH<=0;
        BGR_HIGH<=0;
    end
end  //always posedge clk

task INC_X;             //INCREMENT X COLUMN
begin
    if (X==39) X=0;
    else X=X+1;
    if (DWidth)WParity=~WParity;
    else WParity=0;
    DWidth=0; 
end
endtask

task INC_S;             //INCREMENT SLICE
begin
    if (S==9)begin      //New Row
        S=0;
        INC_Y;
    end
    else S=S+1;
end
endtask

task INC_Y;             //INCREMENT Y ROW
begin
    if (DHeight)HParity=~HParity;
    else HParity=0;
    DHeight=0; 
    if (Y==`Service_Row) begin
        Y=Y0[4:0];
        ZOOM=Y0[5];     // Zoom Mode (Top of page 15)
    end
    else if (Y==23) Y=0;
    else Y=Y+1;
end
endtask

task INC_C;             //STATE DIAGRAM on PAGE 14
begin
    if (XC==39 || XC==47 || XC==55 || XC==63) begin
        XC=0;
        if (YC==23) YC=0;
        else YC=YC+1;
    end
    else XC=XC+1;
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

task ACCESS_MODE;         //Table 3 page 24
begin
    case (`M_Access)
    `AcMode_WriteMP:     begin          //CYCLE TYPE 5 (Page 19)
                            adr=Transcode_C;r_w=0;_sm=0;_st=0;end 
    `AcMode_ReadMP:      begin          //CYCLE TYPE 4 (Page 19)
                            adr=Transcode_C;r_w=1;_sm=0;_st=0;end 
    `AcMode_WriteMP_NI:  begin          //CYCLE TYPE 5 (Page 19)
                            adr=Transcode_C;r_w=0;_sm=0;_st=0;end 
    `AcMode_ReadMP_NI:   begin          //CYCLE TYPE 4 (Page 19)
                            adr=Transcode_C;r_w=1;_sm=0;_st=0;end 
    `AcMode_WriteSlice:  begin          //CYCLE TYPE 7 (Page 19)
                            adr[3:0]<=`M_Slice;r_w=0;_sg=0;_st=0;INC_NT;end 
    `AcMode_ReadSlice:   begin          //CYCLE TYPE 6 (Page 19)
                            adr[3:0]<=`M_Slice;r_w=1;_sg=0;_st=0;INC_NT;end 
    endcase
end
endtask

task INC_NT;
begin
    if (`M_Slice==9) `M_Slice=0;
    else `M_Slice=`M_Slice+1;
end
endtask

task DECODE_WINDOW_CODE;
begin
    if `DELIMITER begin
        C1=AttrL[2:0];
        C0=AttrL[6:4];
        end     
    else if `ALPHANUMERIC begin     //Attributes on bottom of page 20
        C1=AttrL[2:0];
        ATTR=AttrL[6:3];
        SliceVal=((`ATTR_DWIDTH)?                   //Double Width
            (X[0])?{{2{busA[7]}},{2{busA[6]}},{2{busA[5]}},{2{busA[4]}}}:
                   {{2{busA[3]}},{2{busA[2]}},{2{busA[1]}},{2{busA[0]}}}:
                   busA[7:0]) |
                   (Y==9 & UNDERLINE) &              //Underline
                   ~(`R_Blinking & `BLINK_ACTIVE);    //Blinking
        end
    else if `ILLEGAL begin
        SliceVal=8'hFF;
        end
    else begin          //SEMIGRAPHIC
        C1=AttrL[2:0];C0=AttrL[6:4];
        `ATTR_STABLE=AttrL[3];
        end
end
endtask

endmodule
