`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/12/2026 12:01:45 PM
// Design Name: 
// Module Name: splicer_gpio_config
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module splicer_gpio_config(
    input  logic [1:0] quadrant,
    input  logic [3:0] switch,
    output logic [3:0] leds,
    output logic [7:0] header
);

    always_comb begin
        logic [1:0] quad;
        quad = quadrant + switch[1:0];

        leds[0] = (quad == 2'b00) ? 1'b1 : 1'b0;
        leds[1] = (quad == 2'b01) ? 1'b1 : 1'b0;
        leds[2] = (quad == 2'b10) ? 1'b1 : 1'b0;
        leds[3] = (quad == 2'b11) ? 1'b1 : 1'b0;

        header[0] = leds[0];
        header[1] = leds[1];
        header[2] = leds[2];
        header[3] = leds[3];
        header[7:4] = 4'b0;
    end

endmodule