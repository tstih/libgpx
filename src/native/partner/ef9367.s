		;; ef9367.s
        ;; 
        ;; a library of primitives for the thompson ef9367 card (GDP)
        ;; 
        ;; TODO: 
        ;;  - cache drawing modes and pen up/down status to 
        ;;    avoid multiple writes to registers 
		;;
        ;; MIT License (see: LICENSE)
        ;; copyright (c) 2021 tomaz stih
        ;;
		;; 04.04.2021    tstih
		.module ef9367

		.globl	__ef9367_init
        .globl 	__ef9367_cls
        .globl  __ef9367_set_blit_mode
        .globl  __ef9367_put_pixel
        .globl  __ef9367_move_right
        .globl  __ef9367_stride
        .globl  __ef9367_tiny
        .globl  _ef9367_draw_line
	    
		.include "ef9367.inc"


        ;; cached data
        .area   _DATA
blit_mode:
        .db     1                       ; default mode is 1 (BL_COPY)
pen_down:
        .db     1                       ; default is pen down
yrev:
        .dw     1                       ; y reverse axis size

        
        .area	_CODE
        ;; wait for the GDP to finish previous operation
        ;; don't touch interrupts!
        ;; affects: a
wait_for_gdp:
        ;; make sure GDP is free
        in      a,(#EF9367_STS_NI)      ; read the status register
        and     #EF9367_STS_READY       ; get ready flag, it's the same bit
        jr      z,wait_for_gdp
        ret



        ;; executes ef9367 command (wait for status first!)
        ;; input:	a=command
ef9367_cmd:
        push    af
        call    wait_for_gdp            ; wait gdp
        pop     af
        out     (#EF9367_CMD), a        ; exec. command
        ret



        ;; move the cursor to x,y
        ;; notes:   y is transformed bottom to top!
        ;; inputs:  hl=x, de=y
        ;; affect:  af, de, hl
ef9367_xy::
        ;; reverse y coordinate
        push    hl                      ; store x
        ld      hl,(yrev)               ; hl=max y
        or      a                       ; clear carry
        sbc     hl,de                   ; hl=maxy-y
        pop     de                      ; de=x
        ex      de,hl                   ; switch
        ;; wait for gdp
        call    wait_for_gdp
        ld a,l
        out (#EF9367_XPOS_LO),a
        ld a,h
        out (#EF9367_XPOS_HI),a
        ld a,e
        out (#EF9367_YPOS_LO),a
        ld a,d
        out (#EF9367_YPOS_HI),a
        ret


        ;; set deltas to dx, dy
        ;; inputs:  b=dy, c=dx
        ;; affect:  a, bc
ef9367_dxdy::
        call    wait_for_gdp
        ld      a,b
        out     (#EF9367_DY),a
        ld      a,C
        out     (#EF9367_DX),a
        ret


        ;; -------------------
		;; void _ef9367_init()
        ;; -------------------
        ;; initializes the ef9367, sets the 1024x512 graphics mode
        ;; no waiting for gdp bcs no command should be executing!
        ;; affect:  a, bc, flags
__ef9367_init::
        ld      a,#0b00000011           ; pen down, default pen
        out     (#EF9367_CR1),a         ; control reg 1 to default
        xor     a                       ; a=0
        out     (#EF9367_CR2),a         ; control reg 2 to default
        out     (#EF9367_CH_SIZE),a     ; no scaling!
        ;; this sets default (MAX) resolution
        ;; and default page to 0
        ld      a,#PIO_GR_CMN_1024x512  
		out     (#PIO_GR_CMN),a
        ;; cache resolution as yrev(erse)
        ld      hl, #EF9367_HIRES_HEIGHT
        ld      (yrev),hl
        ret



        ;; ------------------
		;; void _ef9367_cls()
        ;; ------------------
		;; clear graphic screen
        ;; affect:  af
__ef9367_cls::
		ld a,#EF9367_CMD_CLS
		call ef9367_cmd
        ret



        ;; set blit mode, use cached mode if necessary
        ;; input:   b = blit mode, one of BL_ codes!
        ;; affects: af, hl, bc, byte@sdm_cache
__ef9367_set_blit_mode:
        ;; are we already in this mode?
        ld      a,(blit_mode)           ; get cached value
        cp      b                       ; compare to current mode
        ret     z                       ; all done!
        ;; write to cache and into a
        ld      a,b                     ; store new mode
        ld      (blit_mode),a           ; to cache
        ;; if none then pen up!
        and     #EF9367_BM_NONE         ; none?
        jr      z, blm_pen_down         ; not none, check xor
        ;; if we are here: PEN UP!
        ld      a,(pen_down)            ; get cached pen status
        or      a                       ; set zero flag
        ret     z                       ; pen is already up!
        ;; set cached pen down to false
        xor     a
        ld      (pen_down),a
        ;; and call pen up
        ld      a,#EF9367_CMD_PEN_UP    ; pen up command
        call    ef9367_cmd              ; execute command.
        ret
        ;; whatever it is, it will require pen down
        ;; if not already down
blm_pen_down:
        ld      a,(pen_down)            ; get cached value
        or      a                       ; compare
        jr      nz,blm_pen_already_down
        ld      a,#1                    ; cached value to 1
        ld      (pen_down),a
        ld      a,#EF9367_CMD_PEN_DOWN  ; pen up command
        call    ef9367_cmd              ; execute command.
blm_pen_already_down:
        ;; first get current common register to a
        call    wait_for_gdp            ; wait for gdp
        in      a,(#PIO_GR_CMN)         ; get current reg. to a
        ld      c,a                     ; store to c
        ;; now toggle the xor flag. 
        ld      a,b                     ; blit mode back to a
        and     #EF9367_BM_XOR          ; is it xor?
        jr      z,blm_copy              ; default = copy!
        ;; it is XOR
        ld      a,c                     ; get back a
        or      #PIO_GR_CMN_XOR_MODE    ; set xor bit
        jr      blm_write               ; write xor value
        ;; it is COPY
blm_copy:
        ld      a,c                     ; get back a
        and     #~PIO_GR_CMN_XOR_MODE   ; clr xor bit
        ;; finally, write back to register.
blm_write:
        push    af
        call    wait_for_gdp            ; wait
        pop     af
        out     (#PIO_GR_CMN),a         ; write it back
        ret


        ;; ------------------------
		;; void _ef9367_put_pixel()
        ;; ------------------------
        ;; draw single pixel 
        ;; affect:  af
__ef9367_put_pixel::
        ld      a,#0x80
        call    ef9367_cmd
		ret


        ;; -------------------------
		;; void _ef9367_move_right()
        ;; -------------------------
        ;; move x to the right
__ef9367_move_right::
        call    wait_for_gdp
        ld      a,#0b00000010           ; pen up
        out     (#EF9367_CR1),a
        ld      a,#0b10100000           ; move right
        call    ef9367_cmd
        call    wait_for_gdp
        ld      a,#0b00000011           ; pen down (again!)
        out     (#EF9367_CR1),a
        ret


        ;; -------------------
		;; void _ef9367_tiny()
        ;; -------------------
        ;; draw fast tiny at (preset) x,y
        ;; inputs: 
        ;;  hl = moves
        ;;  e = number of moves
        ;; affect:  af, de, hl
__ef9367_tiny::
        ld      a,e                     ; moves to b
        or      a                       ; zero moves?
        ret     z
        ld      b,a                     ; b=move counter
tny_loop:
        ld      a,(hl)                  ; move to a
        push    af                      ; store it
        ld      d,#0                    ; assume pen up
        ;; now check pen...
        rlca                            ; get color to first 2 bits
        and     #0b00000011             ; get color
        jr      z,tny_set_pen           ; CO_NONE=raise the pen
        inc     d                       ; pen down to d
tny_set_pen:
        ;; compare d to (pen_down) cached value
        ld      a,(pen_down)
        cp      d
        jr      z,tny_set_color         ; if the same no change
        ;; if we are here we need to change the pen status
        ;; a has the inverse value!
        or      a                       ; cached pen down?
        jr      nz,tny_pen_up           ; pen up
        ;; if we are here, pen down!
        call    wait_for_gdp
        ld      a,#0b00000011           ; pen down
        out     (#EF9367_CR1),a
        and     #1                      ; a=1!
        ld      (pen_down),a            ; write to cache
        jr      tny_set_color
tny_pen_up:
        ;; if we are here, pen up!
        call    wait_for_gdp
        ld      a,#0b00000010           ; pen up
        out     (#EF9367_CR1),a
        xor     a
        ld      (pen_down),a            ; and set cached value
        jr      tny_draw_move           ; done!
        ;; pen is down/up as it should be
        ;; now set the eraser or ink
tny_set_color:
        ;; TODO: implement eraser
tny_draw_move:
        pop     af                      ; move back to a
        inc     hl                      ; next move
        ;; make a move!
        or      #0b10000001             ; set both bits to 1
        xor     #0b00000100             ; negate y sign (rev.axis)
        call    ef9367_cmd              ; and draw!
        ;; and, finally, move!
        djnz    tny_loop                ; and loop
        ret


        ;; ---------------------
		;; void _ef9367_stride()
        ;; ---------------------
        ;; draw fast stride at (preset) x,y
        ;; inputs: 
        ;;  hl = data
        ;;  e=start bit
        ;;  d=end bit
        ;; affect:  af, de, hl
__ef9367_stride::
        ;; calculate difference in pixels
        ld      a,d
        sub     e                       ; a=end-start
        ld      c,a                     ; store to c
        ;; start is in bits, how many bytes to skip?
        xor     a                       ; a=0
        srl     e                       ; e=e/2
        rla                             ; into a
        srl     e                       ; e=e/4
        rla                             ; into a
        srl     e                       ; e=e/8
        rla                             
        ;; e=bytes to skip, a=remainder
        ld      d,#0                    ; de=bytes to skip
        add     hl,de                   ; we are at right byte!
        ;; a=current bit (from the left), c=total bits, hl=address
        ld      d,(hl)                  ; first byte to default
        ;; do we need initial shift?
        or      a                       ; rotate is 0 bits?
        jr      z,strd_start            ; we are ready
        ;; let's do initial shift
        ld      b,a                     ; counter to a
strd_shift:
        sla     d                       ; shift data
        djnz    strd_shift              ; and loop
strd_start:
        ;; at this point - 
        ;;  a is current shift 
        ;;  d is shifted data 
        ;;  hl=address
        ;;  c total number of bits
        ld      b,c                     ; b will be our counter
strd_loop:
        ;; get the bit into carry
        push    af
        sla     d   
        jr      nc,strd_skip_draw       ; no bit?
        ;; draw it
        call    __ef9367_put_pixel   
strd_skip_draw:
        call    __ef9367_move_right
        pop     af
        inc     a                       ; next bit
        cp      #8                      ; across byte boundary?
        jr      nz,strd_get_nxt         ; nope...
        ;; we are across byte boundary
        xor     a                       ; bit is 0 from the left
        inc     hl                      ; next byte
        ld      d,(hl)                  ; into d
strd_get_nxt:
        ;; and next bit
        djnz    strd_loop
        ;; we're done
        ret


        ;; ----------------------
		;; void ef9367_draw_line(
        ;;     uint16_t x0, 
        ;;     uint16_t y0, 
        ;;     uint16_t x1,
        ;;     uint16_t y1,
        ;;     uint8_t mode,
        ;;     uint8_t mask);  
        ;; ----------------------
		;; draws line fast
        ;; affect:  -
_ef9367_draw_line::
        ;; store ix to stack, we'll use it to access args.
        push ix
        ld ix,#4                        ; first arg.
        add ix,sp
        ;; goto xy
        ;; TODO: call xy_internal
        ;; y0 to de
        ld e,2(ix)                      ; de=y0
        ld d,3(ix)
        ;; find delta signs and mex line len
        ld a,#0x11                      ; a will hold the deltas
        or a                            ; clear carry flag
        ld l,6(ix)                      ; hl=y1
        ld h,7(ix)
        push hl                         ; store y1.
        sbc hl,de                       ; hl=y1-y0-c (C=0)
        ;; note: partner has reverse y axis
        jr c, dli_negat_dy              ; y1<y0, no change to delta sign
        pop de                          ; clean the stack (remove y1)
        ;; set flag (remember, reverse y axis!)
        or #4                           ; set flag (bit 2 of a)
        jr dli_dy_done                  ; we're done 
dli_negat_dy:
        pop hl                          ; hl=y1 (again)
        ex de,hl                        ; reverese equation
        sbc hl,de                       ; and make result positive
        inc hl                          ; +1, because of carry
dli_dy_done:
        ex de,hl                         ; de=abs(y1-y0)
        ;; start dx calculation
        ld c,(ix)                       ; bc=x0
        ld b,1(ix)
        ld l,4(ix)                      ; hl=x1
        ld h,5(ix)
        pop ix                          ; restore ix forever to cln. stack
        push de                         ; store abs(y1-y0) to stack
        push hl                         ; store the x1 
        or a                            ; clear carry flag
        sbc hl,bc                       ; hl=x1-x0
        jr nc,dli_posit_dx              ; x1>=x0, sign 0 is ok    
        or #2                           ; set bit 1 of delta to -, C=0
        pop de                          ; de=x1       
        push bc                         ; bc to hl
        pop hl                          ; hl=x0
        sbc hl,de                       ; hl=abs(x0-x1)
        jr dli_dx_done    
dli_posit_dx:
        pop de                          ; clean the stack (remove x1)
dli_dx_done:
        ;; hl = abs(x1-x0) and abs(y1-y0) is already on stack
        pop de                          ; de=abs(y1-y0)
        ;; but push back for later
        push de
        push hl                         ; both distances to stack
        ;; now find longer to find out how many lines 
        ;; hl=dx, de=dy
        or a                            ; clear carry
        sbc hl,de
        jr c,dli_dy_longer
        pop hl                          ; hl is the longer one
        push hl                         ; put it back
        jr dli_draw_lines
dli_dy_longer:
        ex de,hl                        ; move longer one to hl
dli_draw_lines:
        ;; store longer one to stack
        push hl
        ;; set mode
        push af                         ; store draw command
        ld b,8(ix)                      ; mode to b
        ;; TODO: call ef9367_set_dmode
        pop af                          ; restore draw command
        ;; start the recursion. there are four parameters
        ;; on stack (in the pop order): longest coordinate, 
        ;; abs(dx), abs(dy), and return
dli_recursion:
        pop hl                          ; get longest coordinate
        push hl                         ; and store to stack for consistency
        ld de,#EF9367_MAX_DELTA         ; max line we can draw
        or a                            ; clear carry flag
        sbc hl,de                       ; commpare
        jr c, dli_draw_delta            ; end of recursion
        ;; we can't draw this
        ;; find mid point and divide 
        ;; the line to two lines        ;
        exx                             ; we'll need more registers
        pop de                          ; get longest coordinate into de
        push de
        pop hl                          ; AND into hl
        srl d                           ; de=long. coord/2
        rr e
        or a                            ; clear carry
        sbc hl,de                       ; hl=clong. oord-de (/2 for odd numbers!)
        exx
        ;; do the same for dx with std. register sets
        pop de                          ; de=dx
        push de
        pop hl                          ; AND into hl
        srl d                           ; de=dx/2
        rr e
        or a                            ; clear carry
        sbc hl,de                       ; hl=dx-de (/2 for odd numbers!)
        ;; and, finally, for dy use bc and bc' as storage!
        pop bc                          ; bc=dy
        push bc                         ; store back
        push hl                         ; store hl...
        exx 
        pop bc                          ; ...into alt bc
        exx
        pop hl                          ; hl=(also) dy
        srl b                           ; bc=dy/2
        rr c
        or a                            ; clear carry
        sbc hl,bc                       ; hl=dy-dy/2
        ;; we have it all!
        ;; only return address left on staqck at this point, leave it!
        ;; nicely put halved args back to stack in reverse order, longer first!
        push hl                         ; dy2
        exx
        push bc                         ; dx2
        push hl                         ; longer coord. 2
        exx
        ;; now the shorter line
        ld hl,#dli_recursion            ; restart the recursion upon return
        push hl
        push bc                         ; dy1
        push de                         ; dx1
        exx
        push de                         ; shorter longest coord.
        exx
        jr dli_recursion

dli_draw_delta:
        pop hl                          ; longest coord. ... discharge it
        pop hl                          ; hl=dx
        pop de                          ; de=dy
        ld b,l                          ; b=dx
        ld c,e                          ; c=dy 
        ;; superfast line drawing (delta method)
        push af                         ; store command
dli_wait_gdp:
        ;; wait for GDP
        in a,(#EF9367_STS_NI)
        and #EF9367_STS_READY
        jr z,dli_wait_gdp
        ;; set deltas!
        ld a,b
        out (#EF9367_DX),a
dli_wait_gdp2:
        ;; wait for GDP
        in a,(#EF9367_STS_NI)
        and #EF9367_STS_READY
        jr z,dli_wait_gdp2
        ld a,c
        out (#EF9367_DY),a
        pop af
        ;; command is in a
        call ef9367_cmd
        ret