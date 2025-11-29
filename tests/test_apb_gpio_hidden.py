import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# ------------------------------------------------------------
# APB helpers
# ------------------------------------------------------------
async def apb_write(dut, addr, data):
    dut.psel.value = 1
    dut.pwrite.value = 1
    dut.penable.value = 0
    dut.paddr.value = addr
    dut.pwdata.value = data
    await RisingEdge(dut.pclk)   # setup phase

    dut.penable.value = 1
    await RisingEdge(dut.pclk)   # enable/strobe

    dut.psel.value = 0
    dut.penable.value = 0
    await RisingEdge(dut.pclk)   # idle

async def apb_read(dut, addr):
    dut.psel.value = 1
    dut.pwrite.value = 0
    dut.penable.value = 0
    dut.paddr.value = addr
    await RisingEdge(dut.pclk)   # setup phase

    dut.penable.value = 1
    await RisingEdge(dut.pclk)   # enable/strobe
    data = dut.prdata.value.integer

    dut.psel.value = 0
    dut.penable.value = 0
    await RisingEdge(dut.pclk)   # idle
    return data

async def reset(dut):
    dut.presetn.value = 0
    await RisingEdge(dut.pclk)
    dut.presetn.value = 1
    await RisingEdge(dut.pclk)

async def wait_cycles(n, dut):
    for _ in range(n):
        await RisingEdge(dut.pclk)

# ------------------------------------------------------------
# Testbench
# ------------------------------------------------------------
@cocotb.test()
async def apb_gpio_secret_sequence(dut):
    """Full APB GPIO secret_pin sequence test for Option B RTL"""

    # Clock
    cocotb.start_soon(Clock(dut.pclk, 10, units="ns").start())
    await reset(dut)

    # ------------------------------------------------------------
    # 0. Nominal GPIO behavior
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 0xAA)
    val = await apb_read(dut, 0x0)
    assert val == 0xAA, "GPIO normal write/read failed"
    await reset(dut)

    # ------------------------------------------------------------
    # 1. Happy path: 2 -> 4 -> 6, 3-cycle spacing
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 2)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 4)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 6)
    await RisingEdge(dut.pclk)  # toggle latency
    assert dut.secret_pin.value.integer == 1, "Happy path failed: secret_pin did not toggle"
    await reset(dut)

    # ------------------------------------------------------------
    # 2. Too-short timing (2-cycle gap)
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 2)
    await wait_cycles(2, dut)
    await apb_write(dut, 0x0, 4)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 6)
    await RisingEdge(dut.pclk)
    assert dut.secret_pin.value.integer == 0, "Too-short timing incorrectly toggled secret_pin"
    await reset(dut)

    # ------------------------------------------------------------
    # 3. Late sequence (4-cycle gap)
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 2)
    await wait_cycles(4, dut)
    await apb_write(dut, 0x0, 4)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 6)
    await RisingEdge(dut.pclk)
    assert dut.secret_pin.value.integer == 0, "Late sequence incorrectly toggled secret_pin"
    await reset(dut)

    # ------------------------------------------------------------
    # 4. Read between writes
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 2)
    await wait_cycles(1, dut)
    _ = await apb_read(dut, 0x0)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 4)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 6)
    await RisingEdge(dut.pclk)
    assert dut.secret_pin.value.integer == 0, "Read-between-writes incorrectly toggled secret_pin"
    await reset(dut)

    # ------------------------------------------------------------
    # 5. Write to wrong address
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 2)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x4, 4)  # wrong address aborts
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 6)
    await RisingEdge(dut.pclk)
    assert dut.secret_pin.value.integer == 0, "Wrong address write incorrectly toggled secret_pin"
    await reset(dut)

    # ------------------------------------------------------------
    # 6. Non-increasing values
    # ------------------------------------------------------------
    await apb_write(dut, 0x0, 2)
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 2)  # same value
    await wait_cycles(3, dut)
    await apb_write(dut, 0x0, 4)
    await RisingEdge(dut.pclk)
    assert dut.secret_pin.value.integer == 0, "Non-increasing values incorrectly toggled secret_pin"


# ✅ CRITICAL: Pytest wrapper function
def test_apb_gpio_hidden_runner():
    import os
    from pathlib import Path
    from cocotb_tools.runner import get_runner
    
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    
    sources = [proj_path / "sources/apb_gpio_with_secret_toggle.sv"]
    
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="apb_gpio_with_secret_toggle",
        always=True,
    )
    runner.test(
        hdl_toplevel="apb_gpio_with_secret_toggle",
        test_module="test_apb_gpio_hidden"
    )

