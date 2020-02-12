//!import axi/axi4_pkg

`timescale 1ns/1ps

interface axi4_ar_intf
    import axi4_pkg::*;
#(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  valid, ready;
    logic [ADDR_WIDTH-1:0] addr;
    axi4_burst_t           burst;
    axi4_cache_t           cache;
    axi4_len_t             len;
    axi4_lock_t            lock;
    axi4_prot_t            prot;
    axi4_qos_t             qos;
    axi4_size_t            size;
    logic [USER_WIDTH-1:0] user;
    logic [ID_WIDTH-1:0]   id;

    modport out(
        output valid, 
        input ready, 
        output addr, burst, cache, len, lock, prot, qos, size, user, id
    );

    modport in(
        input valid, 
        output ready, 
        input addr, burst, cache, len, lock, prot, qos, size, user, id
    );

    modport view(
        input valid, ready,
        input addr, burst, cache, len, lock, prot, qos, size, user, id
    );

    task send(
        input logic [ADDR_WIDTH-1:0] addr_in,
        input axi4_burst_t           burst_in,
        input axi4_cache_t           cache_in,
        input axi4_len_t             len_in,
        input axi4_lock_t            lock_in,
        input axi4_prot_t            prot_in,
        input axi4_qos_t             qos_in,
        input axi4_size_t            size_in,
        input logic [USER_WIDTH-1:0] user_in,
        input logic [ID_WIDTH-1:0]   id_in
    );
        addr <= addr_in;
        burst <= burst_in;
        cache <= cache_in;
        len <= len_in;
        lock <= lock_in;
        prot <= prot_in;
        qos <= qos_in;
        size <= size_in;
        user <= user_in;
        id <= id_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output logic [ADDR_WIDTH-1:0] addr_out,
        output axi4_burst_t           burst_out,
        output axi4_cache_t           cache_out,
        output axi4_len_t             len_out,
        output axi4_lock_t            lock_out,
        output axi4_prot_t            prot_out,
        output axi4_qos_t             qos_out,
        output axi4_size_t            size_out,
        output logic [USER_WIDTH-1:0] user_out,
        output logic [ID_WIDTH-1:0]   id_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        addr_out = addr;
        burst_out = burst;
        cache_out = cache;
        len_out = len;
        lock_out = lock;
        prot_out = prot;
        qos_out = qos;
        size_out = size;
        user_out = user;
        id_out = id;
    endtask

endinterface

interface axi4_aw_intf 
    import axi4_pkg::*;
#(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  valid, ready;
    logic [ADDR_WIDTH-1:0] addr;
    axi4_burst_t           burst;
    axi4_cache_t           cache;
    axi4_len_t             len;
    axi4_lock_t            lock;
    axi4_prot_t            prot;
    axi4_qos_t             qos;
    axi4_size_t            size;
    logic [USER_WIDTH-1:0] user;
    logic [ID_WIDTH-1:0]   id;

    modport out(
        output valid,
        input ready,
        output addr, burst, cache, len, lock, prot, qos, size, user, id
    );

    modport in(
        input valid,
        output ready,
        input addr, burst, cache, len, lock, prot, qos, size, user, id
    );

    modport view(
        input valid, ready,
        input addr, burst, cache, len, lock, prot, qos, size, user, id
    );

    task send(
        input logic [ADDR_WIDTH-1:0] addr_in,
        input axi4_burst_t           burst_in,
        input axi4_cache_t           cache_in,
        input axi4_len_t             len_in,
        input axi4_lock_t            lock_in,
        input axi4_prot_t            prot_in,
        input axi4_qos_t             qos_in,
        input axi4_size_t            size_in,
        input logic [USER_WIDTH-1:0] user_in,
        input logic [ID_WIDTH-1:0]   id_in
    );
        addr <= addr_in;
        burst <= burst_in;
        cache <= cache_in;
        len <= len_in;
        lock <= lock_in;
        prot <= prot_in;
        qos <= qos_in;
        size <= size_in;
        user <= user_in;
        id <= id_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output logic [ADDR_WIDTH-1:0] addr_out,
        output axi4_burst_t           burst_out,
        output axi4_cache_t           cache_out,
        output axi4_len_t             len_out,
        output axi4_lock_t            lock_out,
        output axi4_prot_t            prot_out,
        output axi4_qos_t             qos_out,
        output axi4_size_t            size_out,
        output logic [USER_WIDTH-1:0] user_out,
        output logic [ID_WIDTH-1:0]   id_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        addr_out = addr;
        burst_out = burst;
        cache_out = cache;
        len_out = len;
        lock_out = lock;
        prot_out = prot;
        qos_out = qos;
        size_out = size;
        user_out = user;
        id_out = id;
    endtask

endinterface

interface axi4_b_intf 
    import axi4_pkg::*;
#(
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                valid, ready;
    axi4_resp_t          resp;
    logic [ID_WIDTH-1:0] id;

    modport out(
        output valid,
        input ready,
        output resp, id
    );

    modport in(
        input valid,
        output ready,
        input resp, id
    );

    modport view(
        input valid, ready,
        input resp, id
    );

    task send(
        input axi4_resp_t            resp_in,
        input logic [ID_WIDTH-1:0]   id_in
    );
        resp <= resp_in;
        id <= id_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output axi4_resp_t            resp_out,
        output logic [ID_WIDTH-1:0]   id_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        resp_out = resp;
        id_out = id;
    endtask

endinterface

interface axi4_r_intf 
    import axi4_pkg::*;
#(
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  valid, ready;
    logic [DATA_WIDTH-1:0] data;
    logic                  last;
    axi4_resp_t            resp;
    logic [ID_WIDTH-1:0]   id;

    modport out(
        output valid,
        input ready,
        output data, last, resp, id
    );

    modport in(
        input valid,
        output ready,
        input data, last, resp, id
    );

    modport view(
        input valid, ready,
        input data, last, resp, id
    );

    task send(
        input logic [DATA_WIDTH-1:0] data_in,
        input logic                  last_in,
        input axi4_resp_t            resp_in,
        input logic [ID_WIDTH-1:0]   id_in
    );
        data <= data_in;
        last <= last_in;
        resp <= resp_in;
        id <= id_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output logic [DATA_WIDTH-1:0] data_out,
        output logic                  last_out,
        output axi4_resp_t            resp_out,
        output logic [ID_WIDTH-1:0]   id_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        data_out = data;
        last_out = last;
        resp_out = resp;
        id_out = id;
    endtask

endinterface

interface axi4_w_intf 
    import axi4_pkg::*;
#(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                    valid, ready;
    logic [DATA_WIDTH-1:0]   data;
    logic [STROBE_WIDTH-1:0] strb;
    logic                    last;

    modport out(
        output valid,
        input ready,
        output data, strb, last
    );

    modport in(
        input valid,
        output ready,
        input data, strb, last
    );

    modport view(
        input valid, ready,
        input data, strb, last
    );

    task send(
        input logic [DATA_WIDTH-1:0]   data_in,
        input logic [STROBE_WIDTH-1:0] strb_in,
        input logic                    last_in
    );
        data <= data_in;
        strb <= strb_in;
        last <= last_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output logic [DATA_WIDTH-1:0]   data_out,
        output logic [STROBE_WIDTH-1:0] strb_out,
        output logic                    last_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        data_out = data;
        strb_out = strb;
        last_out = last;
    endtask

endinterface
