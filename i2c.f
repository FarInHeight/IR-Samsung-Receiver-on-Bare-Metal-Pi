\ There are 8 Broadcom Serial Control (BSC) controllers, numbered from 0 to 7
\ Only 6 of these masters can be used, because BSC masters 2 and 7 are not user-accessible.
\ Since GPIO pins 2 and 3 are used, BSC1 is the reference master.
804000 CONSTANT BSC1

\ There are 8 I2C registers, each of which is at an address obtained by applying an
\ offset to BSC1 (this process is the same for all BSCs).
\ I2C registers are:
\ - C register          The control register is used to enable interrupts, clear the FIFO, 
\                       define a read or write operation and start a transfer;
\ - S register          The status register is used to record activity status, errors 
\                       and interrupt requests;
\ - DLEN register       The data length register defines the number of bytes of data 
\                       to transmit or receive in the I2C transfer. Reading the 
\                       register gives the number of bytes remaining in the current 
\                       transfer;
\ - A register          The slave address register specifies the slave address and cycle type.
\                       The address register can be left across multiple transfers;
\ - FIFO register       The Data FIFO register is used to access the FIFO. Write cycles 
\                       to this address place data in the 16-byte FIFO, ready to 
\                       transmit on the BSC bus. Read cycles access data received from 
\                       the bus;
\ - DIV register        The clock divider register is used to define the clock speed of the 
\                       BSC peripheral;
\ - DEL register        The data delay register provides fine control over the 
\                       sampling/launch point of the data;
\ - CLKT Register       The clock stretch timeout register provides a timeout on how long the
\                       master waits for the slave to stretch the clock before deciding that 
\                       the slave has hung.

\ The following constants are defined to point to the registers above.
\ DIV, DEL and CLKT can be left whitout changes.
BSC1 PERI_BASE +             CONSTANT C
BSC1 PERI_BASE + 04 +        CONSTANT S
BSC1 PERI_BASE + 08 +        CONSTANT DLEN
BSC1 PERI_BASE + 0C +        CONSTANT A
BSC1 PERI_BASE + 10 +        CONSTANT FIFO
BSC1 PERI_BASE + 14 +        CONSTANT DIV
BSC1 PERI_BASE + 18 +        CONSTANT DEL
BSC1 PERI_BASE + 1C +        CONSTANT CLKT

\ Set slave address.
\ It can be left across multiple transfers.
: SET_SLAVE ( slave_address -- ) 
    A ! ;

\ Set number of data bytes to transfer.
: SET_DLEN ( length -- ) 
    DLEN ! ;

\ Place 8 bits at a time in FIFO in order to transmit them on the BSC bus.
: APPEND ( 8_bit_data -- )
    FIFO ! ;

\ Reset status for subsequent transfers.
\ Only CLKT (9), ERR (8) and DONE (1) can be cleared (W1C type), all other flags are read-only (RO). 
: RESET_STATUS ( -- )
    302 S ! ;

\ Clear FIFO.
\ - CLEAR (5:4) set to X1 or 1X in order to clear the FIFO before the new frame is started.
: CLEAR_FIFO ( -- )
    10 C ! ;

\ Modify control register to trigger a transfer.
\ To start a new transfer, all bits are zero except for:
\ - I2CEN (15) set to 1 to enable the BSC controller;
\ - ST (7) set to 1 to start a new transfer (one-shot operation).
\ Interrupts are disabled.
: SET_TRANSFER ( -- )
    8080 C ! ;

\ Data transfer through the I2C bus interface.
\ Since communication is established to the LCD panel, 8 bits at a time are sent.
: TO_I2C
    RESET_STATUS
    CLEAR_FIFO
    1 SET_DLEN
    APPEND
    SET_TRANSFER ;

\ Setup the I2C bus interface and the slave address.
\ Configure GPIO pin 2 for Serial Data Line.
\ Configure GPIO pin 3 for Serial Clock Line.
\ Set the slave address to 0x27.
: I2C_SETUP
    2 ALT0 CONFIGURE
    3 ALT0 CONFIGURE
    27 SET_SLAVE ;

\ Consider the following structure of data transfer:
\           D7 D6 D5 D4 Backlight Enable Read/Write Register-Select
\ equivalently:
\           D7 D6 D5 D4 BL EN RW RS
\ In order to send a byte, it must be decomposed in two nibbles, upper nibble and lower
\ nibble. Each nibble represented by D7 D6 D5 D4 must be followed by a combination of
\ BL EN RW RS.
\ For each data or command to transfer RW = 0.
\ Given a byte B = HIGH LOW (upper-nibble lower-nibble), if it is part of a command,
\ then transfer is obtained by sending:
\   HIGH 1 1 0 0 -> HIGH 1 0 0 0 -> LOW 1 1 0 0 -> LOW 1 0 0 0
\ If it part of a data transfer then:
\   HIGH 1 1 0 1 -> HIGH 1 0 0 0 -> LOW 1 1 0 1 -> LOW 1 0 0 0
\ RS is equal to 0 for instruction input and it is equal to 1 for data input.


\ Returns setting parts to be sent based on a truth value that indicates whether the input
\ is part of a command or data.
: SETTINGS ( truth_value -- first_setting second_setting )
    IF 
        0C 08
    ELSE 
        0D 08
    THEN ;

\ Returns a nipple aggregated with the first setting part and the second setting part.
: AGGREGATE ( settings byte -- nipple_second_setting nipple_first_setting )
    4 LSHIFT DUP ROT OR -ROT OR ;

\ Divides a byte into two nipples.
: BYTE_TO_NIPPLES ( byte -- lower_nipple upper_nipple )
    DUP 0F AND SWAP 4 RSHIFT 0F AND ;

\ Send a nipple to LCD aggregated with settings.
: SEND_NIPPLE ( nipple truth_value -- )
    SETTINGS ROT
    AGGREGATE
    TO_I2C 1000 DELAY
    TO_I2C 1000 DELAY ;

\ Transmits input to LCD given an instruction or data.
: TO_LCD ( input -- )
    DUP 8 WORD_TO_BIT >R
    BYTE_TO_NIPPLES R@
    SEND_NIPPLE R>
    SEND_NIPPLE ;
