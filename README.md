# APB3 GPIO Controller with Secret Output Toggle

A SystemVerilog implementation of an 8-bit GPIO controller with an APB3 interface, featuring a hidden secret-pin toggle mechanism triggered by a defined write sequence.

Overview

This project implements a minimal 8-bit GPIO controller accessible through a standard APB3 bus.
In addition to normal read/write behavior, the controller contains a hidden state machine that toggles a secret_pin output when a strict 3-write sequence is detected with correct timing and no interruptions.
## Features

- **APB3 Interface**: Standard 2-cycle APB protocol support
- **8-bit GPIO Register**: Read/write access to GPIO data register
- **Secret Pin Toggle**: Hidden behavior triggered by a specific write sequence
- **Synthesizable RTL**: SystemVerilog implementation ready for synthesis

## Project Structure

```
apb_gpio_ctrl/
├── rtl/                          # RTL source files
│   └── apb_gpio_ctrl.sv         # Main module implementation
├── harness/                      # Test harness
│   ├── sources/                  # Reference implementations
│   └── tests/                    # Test files
│       ├── apb_gpio_ctrl_test_hidden.py  # Cocotb testbench
│       └── pytest_apb_gpio_ctrl.py        # Pytest runner
├── docs/                         # Documentation
│   └── Specification.md          # Detailed specification
└── pyproject.toml                # Python project configuration
```

## Module Interface

```systemverilog
module apb_gpio_with_secret_toggle (
    input  logic        pclk,        // APB clock
    input  logic        presetn,      // Active-low async reset
    input  logic        psel,         // APB select
    input  logic        penable,      // APB enable
    input  logic        pwrite,       // APB write/read
    input  logic [31:0] paddr,        // APB address
    input  logic [31:0] pwdata,       // APB write data
    output logic [31:0] prdata,       // APB read data
    output logic        pready,       // APB ready
    output logic        secret_pin    // Secret pin (toggles on magic sequence)
);
```

## Register Map

| Offset | Name | Access | Bits | Description | Reset |
|--------|------|--------|------|-------------|-------|
| 0x00   | GPIO | RW     | [7:0]| GPIO data register | 0x00 |

**Note**: Only the lower 8 bits of the 32-bit APB interface are used.

Normal Behavior

Write - Writing to address 0x00 updates the 8-bit GPIO register
Read - Reading from 0x00 returns the current GPIO value

APB Protocol
The design follows the standard APB3 2-phase handshake:

Setup cycle: psel = 1, penable = 0
Enable cycle: psel = 1, penable = 1
Transfer sampled on rising edge during enable cycle
pready is always 1, indicating no wait states

Secret Hidden Behavior (Sequence Detection)

secret_pin toggles only if the following sequence occurs:
Three APB writes to the GPIO register at address 0x00
Data values must be exactly:
even and greater than prev input and from 0-10


Constraint:
Three writes to 0x00 occur with strictly increasing values chosen from {0, 2, 4, 6, 8, 10}.
Exactly 3 pclk cycles must occur between each write.
No reads or writes to other addresses can occur between the three writes.
Writes must be strictly increasing (second > first, third > second).
Any deviation (wrong value, wrong cycle spacing, read, or write to another address) aborts the sequence immediately.

