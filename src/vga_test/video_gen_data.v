module  video_gen_data
#(
    parameter   H_TOTAL =   1920    ,
    parameter   V_TOTAL =   1080    ,
    parameter   PPC     =   4       ,
    parameter   BPC     =   8

)
(
    input   wire                        video_clk       ,
    input   wire                        rst_n           ,

    output  wire                        video_gen_vs    ,
    output  wire                        video_gen_hs    ,
    output  wire                        video_gen_de    ,
    output  wire    [3*BPC*PPC-1:0]     video_gen_data
);


wire    [23:0]  pixel_data;
screen_test#(

    .PPC        ( PPC         ),
    .BPC        ( BPC         ),
    .H_TOTAL    ( H_TOTAL/PPC ),
    .V_TOTAL    ( V_TOTAL     )   
)u_screen_test(
    .video_clk  ( video_clk       ),
    .rst_n      ( rst_n           ),
    .hsync      ( video_gen_hs    ),
    .vsync      ( video_gen_vs    ),
    .de         ( video_gen_de    ),
    .pixel_data ( pixel_data      )
);



generate
    if(PPC == 4)
    begin
        assign video_gen_data = {4{pixel_data}};

    end
    else    if(PPC == 1)
    begin
        assign video_gen_data = pixel_data;

    end

endgenerate





endmodule