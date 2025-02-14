iverilog -DSIM -g2012 -o tb_sys tb_sys.v ..\src\sys\sys.v ..\src\sys\uart_rx.v ..\src\sys\uart_tx.v
@if errorlevel 1 (
    @echo Compilation failed
    @exit /b 1
)
vvp tb_sys
