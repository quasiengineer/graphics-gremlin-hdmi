// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`default_nettype none
module mda(
    // Clocks
    input clk,

    // ISA bus
    input[19:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input bus_memr_l,
    input bus_memw_l,
    input[7:0] bus_d,
    output[7:0] bus_out,
    output bus_dir,
    input bus_aen,

    // RAM
    output ram_we_l,
    output[18:0] ram_a,
    inout[7:0] ram_d,

    // Video outputs
    output hsync,
    output vsync,
    output video,
    output intensity,
    output display_enable_mda
    );

    parameter MDA_70HZ = 1;
    parameter BLINK_MAX = 0;

    localparam INITIAL_CHAR = 8'h20;             // character shown by default, until we got first access to video RAM
    localparam INITIAL_CHAR_ATTR = 8'b00011000;  // attribute = NO BLINK + INTENSITY + NO UNDERLINE
    localparam POST_CODE_VRAM_POSITION = 12'd78; // position (0, 78) for 80-column text mode

    wire crtc_cs;
    wire status_cs;
    wire control_cs;
    wire bus_mem_cs;

    reg[7:0] bus_int_out;
    wire[7:0] bus_out_crtc;
    wire[7:0] bus_out_mem;
    wire[7:0] mda_status_reg;
    reg[7:0] mda_control_reg = 8'b0010_1000;
    wire video_enabled;
    wire blink_enabled;

    wire hsync_int;
    wire vsync_l;
    wire cursor;
    wire video;
    wire display_enable;
    wire intensity;

    wire[13:0] crtc_addr;
    wire[4:0] row_addr;

    wire charrom_read;
    wire disp_pipeline;
    wire isa_op_enable;
    wire vram_read_char;
    wire vram_read_att;
    wire vram_read;
    wire vram_read_a0;
    wire[4:0] clkdiv;
    wire crtc_clk;
    wire[7:0] ram_1_d;

    reg[23:0] blink_counter;
    reg blink;

    reg bus_memw_synced_l;
    reg bus_memr_synced_l;
    reg bus_ior_synced_l;
    reg bus_iow_synced_l;

    wire[7:0] char_to_display;
    wire show_blank_char;
    reg vram_has_been_accessed = 0;
    wire show_post_code_high_digit;
    wire show_post_code_low_digit;
    wire post_code_present;
    wire[7:0] post_code_high_digit;
    wire[7:0] post_code_low_digit;

    // Synchronize ISA bus control lines to our clock
    always @ (posedge clk)
    begin
        bus_memw_synced_l <= bus_memw_l;
        bus_memr_synced_l <= bus_memr_l;
        bus_ior_synced_l <= bus_ior_l;
        bus_iow_synced_l <= bus_iow_l;
    end

    // Some modules need a non-inverted vsync trigger
    assign vsync = ~vsync_l;

    // Mapped IO
    assign crtc_cs = (bus_a[19:3] == 17'b1110110 ) & ~bus_aen; // 3B4/3B5
    assign status_cs = (bus_a == 20'h3BA) & ~bus_aen;
    assign control_cs = (bus_a == 20'h3B8) & ~bus_aen;

    // Memory-mapped from B0000 to B7FFF
    assign bus_mem_cs = (bus_a[19:15] == 5'b10110);

    // check if we ever had access to VRAM
    always @ (*)
    begin
        if (bus_mem_cs) begin
            vram_has_been_accessed <= 1;
        end
    end

    // Mux ISA bus data from every possible internal source.
    always @ (*)
    begin
        if (bus_mem_cs & ~bus_memr_l) begin
            bus_int_out <= bus_out_mem;
        end else if (status_cs & ~bus_ior_l) begin
            bus_int_out <= mda_status_reg;
        end else if (crtc_cs & ~bus_ior_l & (bus_a[0] == 1)) begin
            bus_int_out <= bus_out_crtc;
        end else begin
            bus_int_out <= 8'h00;
        end
    end

    // Only for read operations does bus_dir go high.
    assign bus_dir = ((crtc_cs | status_cs) & ~bus_ior_l) |
                    (bus_mem_cs & ~bus_memr_l);
    assign bus_out = bus_int_out;


    // MDA status register (read only at 3BA)
    assign mda_status_reg = {4'b1111, video, 2'b00, hsync_int};

    // MDA mode control register (write only)
    assign blink_enabled = mda_control_reg[5];
    assign video_enabled = mda_control_reg[3];

    // Hsync only present when video is enabled
    assign hsync = video_enabled & hsync_int;

    // Update control register
    always @ (posedge clk)
    begin
        if (control_cs & ~bus_iow_synced_l) begin
            mda_control_reg <= bus_d;
        end
    end

    // CRT controller (MC6845 compatible)
    crtc6845 crtc (
        .clk(clk),
        .divclk(crtc_clk),
        .cs(crtc_cs),
        .a0(bus_a[0]),
        .write(~bus_iow_synced_l),
        .read(~bus_ior_synced_l),
        .bus(bus_d),
        .bus_out(bus_out_crtc),
        .lock(MDA_70HZ == 1),
        .hsync(hsync_int),
        .vsync(vsync_l),
        .display_enable(display_enable),
        .display_enable_mda(display_enable_mda),
        .cursor(cursor),
        .mem_addr(crtc_addr),
        .row_addr(row_addr)
    );

    if (MDA_70HZ) begin
        defparam crtc.H_TOTAL = 8'd99;
        defparam crtc.H_DISP = 8'd80;
        defparam crtc.H_SYNCPOS = 8'd82;
        defparam crtc.H_SYNCWIDTH = 4'd12;
        defparam crtc.V_TOTAL = 7'd31;
        defparam crtc.V_TOTALADJ = 5'd1;
        defparam crtc.V_DISP = 7'd25;
        defparam crtc.V_SYNCPOS = 7'd27;
        defparam crtc.V_MAXSCAN = 5'd13;
        defparam crtc.C_START = 7'd11;
        defparam crtc.C_END = 5'd12;
    end else begin
        defparam crtc.H_TOTAL = 8'd97;
        defparam crtc.H_DISP = 8'd80;
        defparam crtc.H_SYNCPOS = 8'd82;
        defparam crtc.H_SYNCWIDTH = 4'd15;
        defparam crtc.V_TOTAL = 7'd25;
        defparam crtc.V_TOTALADJ = 5'd6;
        defparam crtc.V_DISP = 7'd25;
        defparam crtc.V_SYNCPOS = 7'd25;
        defparam crtc.V_MAXSCAN = 5'd13;
        defparam crtc.C_START = 7'd11;
        defparam crtc.C_END = 5'd12;
    end

    // Interface to video SRAM chip
    mda_vram video_buffer (
        .clk(clk),
        .isa_addr({3'b000, bus_a[15:0]}),
        .isa_din(bus_d),
        .isa_dout(bus_out_mem),
        .isa_read(bus_mem_cs & ~bus_memr_synced_l),
        .isa_write(bus_mem_cs & ~bus_memw_synced_l),
        .pixel_addr({7'h00, crtc_addr[10:0], vram_read_a0}),
        .pixel_data(ram_1_d),
        .pixel_read(vram_read),
        .ram_a(ram_a),
        .ram_d(ram_d),
        .ram_we_l(ram_we_l),
        .isa_op_enable(isa_op_enable)
    );

    defparam video_buffer.MDA_70HZ = MDA_70HZ;

    post_code post_code_monitor(
        .clk(clk),
        .isa_addr_en(bus_aen),
        .isa_io_write(bus_iow_synced_l),
        .isa_addr(bus_a),
        .isa_data(bus_d),
        .post_code_present(post_code_present),
        .post_code_high_digit(post_code_high_digit),
        .post_code_low_digit(post_code_low_digit)
    );

    assign show_post_code_high_digit = (vram_read_char && crtc_addr == POST_CODE_VRAM_POSITION && post_code_present);
    assign show_post_code_low_digit = (vram_read_char && crtc_addr == (POST_CODE_VRAM_POSITION + 1) && post_code_present);
    assign show_blank_char = !show_post_code_high_digit && !show_post_code_low_digit && !vram_has_been_accessed;
    assign char_to_display = show_blank_char 
      ? (vram_read_char ? INITIAL_CHAR : INITIAL_CHAR_ATTR)
      : (show_post_code_high_digit ? post_code_high_digit : (show_post_code_low_digit ? post_code_low_digit : ram_1_d));

    // Sequencer state machine
    mda_sequencer sequencer (
        .clk(clk),
        .clk_seq(clkdiv),
        .vram_read(vram_read),
        .vram_read_a0(vram_read_a0),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .crtc_clk(crtc_clk),
        .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline),
        .isa_op_enable(isa_op_enable)
    );

    defparam sequencer.MDA_70HZ = MDA_70HZ;

    // Pixel pusher
    mda_pixel pixel (
        .clk(clk),
        .clk_seq(clkdiv),
        .vram_data(char_to_display),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read),
        .display_enable(display_enable),
        .cursor(cursor),
        .row_addr(row_addr),
        .blink_enabled(blink_enabled),
        .blink(blink),
        .video_enabled(video_enabled),
        .video(video),
        .intensity(intensity)
    );

    // Generate blink signal for cursor and character
    always @ (posedge clk)
    begin
        if (blink_counter == BLINK_MAX) begin
            blink_counter <= 0;
            blink <= ~blink;
        end else begin
            blink_counter <= blink_counter + 1;
        end
    end

endmodule
