# APB3 GPIO Controller with Secret Output Toggle

Implement an 8-bit APB GPIO controller with one register at offset 0x00.

## Registers

- GPIO (RW, lower 8 bits only)

## Hidden magic sequence (hard part)

The output `secret_pin` must toggle (0→1 or 1→0) only when:

1. Three writes to 0x00 occur with **strictly increasing values** chosen from {0, 2, 4, 6, 8, 10}.  
2. Exactly **3 `pclk` cycles** must occur between each write.  
3. **No reads or writes to other addresses** can occur between the three writes.  
4. Writes must be **strictly increasing** (second > first, third > second).  
5. Any deviation (wrong value, wrong cycle spacing, read, or write to another address) **aborts the sequence immediately**.

Normal APB GPIO behavior must function correctly.

## Interface (do not change)

```systemverilog
module apb_gpio_with_secret_toggle (
    input  logic        pclk,
    input  logic        presetn,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        secret_pin
);
