; Mintaptogram egyszeru IT rendszer demonstrálására (programozó: Benesóczky Zoltán)
; Nyomógomb (BT0) változása IT-t okoz, lenyomás esetén 1db 1-est tartalmazó LD_var változót
; jobbra rotál.
; Timer IT 1sec-ra van állítva. Minden páratlan periódusnál elobbi változót, párosnál pedig 0-t
; ír az LD kijelzore. Így egy villogó LED minden BT0 lenyomásnál arréb vándorol.
; A foprogram végtelen ciklusa az SW értékét írja ki a 7 szegmenses kijelzore.
; Ezt szakítják meg az elobbi IT-k.
; Minden IT esetén a 0x01 címre adódik a vezérlés (egyszeru IT rendszer).
; Interrupt elején a flagek automatikusan a STACK-re mentodnek.
; (Nem minden mikrokontroller menti automatikusan!)
; Az IT elején az IT rutinban használt regisztereket el kell menteni,
; hogy a megszakított program regiszter változóit ne írja felül.
; Az IT-bol visszatérés elott (rti) a regiszterek elmentett értékét vissza kell állítani.
; Az IT rutin a megszakítás forrását a periféria státusának lekérdezésével határozza meg.
; A megfelelo periféria kezelo rutint meghívja (tim_IT, BT_IT)

;Periféria cím definíciók:
DEF LD   0x80
DEF SW   0x81                ; switch

; timer
DEF TR   0x82                ; Timer kezdoállapot regiszter         (csak írható)
DEF TM   0x82                ; Timer számláló regiszter             (csak olvasható)
DEF TC   0x83                ; Timer parancs regiszter              (csak írható)
DEF TS   0x83                ; Timer státusz regiszter              (csak olvasható)

; button
DEF BT   0x84                ; Nyomógomb adatregiszter              (csak olvasható)
DEF BTIE 0x85                ; Nyomógomb megszakítás eng. regiszter (írható/olvasható)
DEF BTIF 0x86                ; Nyomógomb megszakítás flag regiszter (olvasható és a bit 1 beírásával törölheto)

; number display
DEF DIG0 0x90                
DEF DIG1 0x91                
DEF DIG2 0x92              
DEF DIG3 0x93       
        
; matrix display       
DEF COL0 0x94           
DEF COL1 0x95
DEF COL2 0x96
DEF COL3 0x97
DEF COL4 0x98


; TIE,TPS2,TPS1,TPS0,-,-,TREP,TEN   TPS2-0:  0:2^0, 1:2^4, 2:2^6, 3:2^8, 4:2^10, 5:2^12, 6:2?14, 7:2^16 
;   1,   1,   1,   0,0,0,1   ,1
DEF TIM_cmd 0b11110011    ; IT engedélyezés, eloosztás 32764, ciklikus muködés, engedélyezés
DEF TIT 0x80        ; Timer IT státus mask

DEF BTIE_mask 0x03  ; használt nyomógombok helye 
DEF BT0 0x01        ; BT0 bit pozíciója
DEF BT1 0x02        ; BT1

    CODE    ;program memória szegmens
start:
    jmp main                ;RESET belépési pont
    
;minden IT belépési pontja (egyszeru IT rendszer)    
;használt regiszterek: r12-r14
IT_entry:                   
TIM_test:                   ;IT_entry(){
    mov r13,TS              ;   TScopy = TS    // timer státus beolvasás és törlés (a beolvasás törli)
    tst r13,#TIT            ;   if(TScopy & TIT != 0)  //Ha timer IT volt
    jz BT_test              ;   {
    jsr tim_IT              ;       tim_IT()}
BT_test:                    ;   else
    mov r13, BTIF           ;      { BTIFcopy = BTIF    //a BTIF flagek lenyomáskor és felengedéskor is bebillennek
    mov r12, #BTIE_mask
    mov BTIF, r12           ;       BTIF = 0 // BTIT flagek törlése
    tst r13, r12            ;       if(BTIFcopy & BTIE_MASK!=0)
    jz IT_end               ;       {
    mov r12,BT
    and r13,r12             ;           PRESSED = BTIF & BT    // a lenyomott gomboknál a bitek 1-ek (r13 = PRESSED)
    jsr BT_IT               ;           BT_IT()}
IT_end:                     ;       }
    rti                     ;}


;TIMER IT 
;IT frekvencia: 16E6/32768/243 => 0.5Hz
tim_IT:                     ;tim_IT()
    cmp r8, #0   ; if( state == PAUSE )
    jz tim_pause 
    
    cmp r6, #1 ; if( labday != 1 )
    jnz SKIP_test
    
    ; test if it is hitting the pallet or not
    add r10, #1 ; ++score
    tst r5, r4 ; if labdax and pallet  don't overlap
    jnz SKIP_test
    
    sub r10, #1 ; --score
    mov r8, #0  ; state = PAUSE
    and r7, #2  ; change dir.dir to right

    SKIP_test:
    
    
    ; increase high_score if score is greater than it
    mov r12, r11
    sub r12, r10
    tst r12, #0x80
    jz SKIP_new_high
    
    mov r11, r10
    
    SKIP_new_high:
    
    jsr update_labda_pos
    jsr update_labda_dir
    
    ; if we are hitting a corner?
    
    tst r5, r4 ; if labdax and pallet  don't overlap
    jz cap_score
    cmp r6, #1 ; if( labday != 1 )
    jnz cap_score
    cmp r5, #1
    jz cap_score
    cmp r5, #64
    jz cap_score
    jsr update_labda_dir_pallet
    
    cap_score:
    ; if we went past 99 score
    cmp r10, #100
    jnz tim_IT_end
    mov r10, #99
    mov r11, #99

    tim_pause:; skipped stuff
        
    tim_IT_end:                 
        mov r12, TIM_per
        mov TR, r12              ;   TR = TIM_per        //  0-99 között számol: 100-zal oszt
        mov TM, r12              
    rts

update_labda_pos:
    ; move angle vertical
    tst r7, #2 ; if( dir.angle == up )
    jz move_up
    move_down:
        rol r5 ; move labda down
        jmp ud_end
    move_up:
        ror r5 ; move labda up
    ud_end:    
    
    ; move dir horizontal
    tst r7, #1 ; if( dir.dir == right )
    jz move_right
    move_left:
        add r6, #1 ; move left
        jmp lr_end
    move_right:
        sub r6, #1 ; move right
    lr_end:
    rts ; return


update_labda_dir_pallet:
    mov r12, r5
    ror r12
    tst r12, r4 ; if moving the ball up will cause it to not collide
    jz dir_down
    dir_up:
        or r7, #2
        jmp dir_none
    dir_down:
        and r7, #1
    dir_none:
    rts

update_labda_dir:
    test_dir:
        cmp r6, #1 ; if got to right wall
        jz change_dir      
        cmp r6, #4 ; if got to left wall
        jz change_dir    
        jmp test_angle
    change_dir: 
        xor r7, #1 ; change dir

    test_angle:
        cmp r5, #1 ; if got to up wall
        jz change_angle
        cmp r5, #64 ; if got to down wall
        jz change_angle
        jmp change_none
    change_angle:
        xor r7, #2 ; change angle

    change_none:
    rts

; Button pressed
BT_IT:                      
    tst r13, #BT0  
    jz BT_IT_1    ; if( r13[0] ) goto BT_IT_1;
    ; if at the end, don't move
    cmp r4, #3
    jz BT_IT_1 ; if( pallet == 0000_0011 )
    ; move right
    ror r4                 
    BT_IT_1:
        tst r13, #BT1
        jz BT_IT_game_end
        ; if at the end, don't move
        cmp r4, #96
        jz BT_IT_game_end ; if( pallet == 0110_0000 )
        ; move left
        rol r4
    BT_IT_game_end:
        cmp r8, #1 ; if state == GAME: jump over reset
        jz BT_IT_end    
    PAUSE:    
    ; reset stuff
    mov r10, #0 ; score = 0
    mov r8, #1 ; state = GAME
    
    mov r6, #4 ; labday
    mov r7, #0 ; iranyok
    
    ;mov r5, #8 ; labdax
    
    ; random starting x
    mov r12, TR ; random is from time
    and r12, #0b00000111 ; 0-7
    cmp r12, #0 ; if 7 then decrement
    jnz skip_sub
        sub r12, #1
    skip_sub:
    cmp r12, #0 ; if 0 then increment
    jnz skip_add
        add r12, #1
    skip_add:
    
    ; rol 1 r12 times
    mov r5, #1
    labdax_loop:
        rol r5
        sub r12, #1
        cmp r12, #0
        jnz labdax_loop
    ror r5    
    
    ; randomize diretion
    mov r12, TR
    and r12, #0b00000010
    mov r7, r12
    
    ; if it is at one of the corners enforce direction
    cmp r5, #1
    jnz dont_set_down
        or r7, #2
    dont_set_down:
    
    cmp r5, #64
    jnz dont_set_up
        and r7, #1
    dont_set_up:
    BT_IT_end:          
        rts                     
    


init:       
    ; initialize globals                
    mov r11, #0 ; high_score
    mov r10, #0 ; score
    mov r5, #4 ; labdax
    mov r6, #4 ; labday
    mov r7, #3 ; direction
    mov r8, #0 ; state - 0 pause, 1 - game
    mov r4, #3 ; pallet
    
    ;; ?????? ;;
    mov r0, #BTIE_mask      ;{
    mov BTIE, r0            ;   BTIE = BTIE_mask    // BT0 IT kérés engedélyezése
    mov r0, TIM_per
    mov TR, r0              ;   TR = TIM_per        //  0-99 között számol: 100-zal oszt
    mov TM, r0              ; 
    mov r0, #TIM_cmd        ;   TM = TIM_cmd        // 16-os eloosztás, periodikus muködés timer és timer IT engedélyezve
    mov TC, r0
    mov r0, #0
    ;; ?????? ;;
       
    sti                     ; globális IT engedélyezés
    rts                     ;
 

print_r1_to_r0:
    mov r2, #0
    tens_loop:
        sub r1, #10
        add r2, #1
        tst r1, #0b10000000
        jz tens_loop
       
    add r1, #10
    sub r2, #1
    
    mov LD, r1

  
    add r2, #hex7seg
    mov r2, (r2)
    mov (r0), r2
    
    
    
    mov r2, #0
    ones_loop:
        sub r1, #1
        add r2, #1
        tst r1, #0x80
        jz ones_loop
    add r1, #1
    sub r2, #1
    
    
    
    add r2, #hex7seg
    mov r2, (r2)
    sub r0, #1
    mov (r0), r2

    rts

 main:                      
    jsr init                
 main_loop:                 
    ; set timer speed?
    mov r1, SW    
    and r1, #0b00000011
    add r1, #times
    mov r1, (r1)
    mov TIM_per, r1 ; TIM_per = SW

    ; draw:
        ; clear matrix
        mov r1, #0
        mov COL0, r1
        mov COL1, r1
        mov COL2, r1
        mov COL3, r1
        mov COL4, r1
        
        cmp r6, #0
        jz draw_col0
        
        ; draw pallet
        mov COL0, r4 ; COL0 = pallet

        ;draw labda:
        mov r1, #COL0 
        add r1, r6
        mov (r1), r5 ; COL[r6] = r5
        
        jmp dont_draw_col0
        draw_col0:
            mov r1, r4
            or r1, r5
            mov COL0, r1
            
        dont_draw_col0:    
     
        
    
    mov r1, TM   
    mov LD, r1 ; display TR to LD ( debug )
   
   ;print scores
    mov r0, #DIG1
    mov r1, r10
    jsr print_r1_to_r0
    
    ; print high_score
    mov r0, #DIG3
    mov r1, r11
    jsr print_r1_to_r0
    
    
    jmp main_loop           
                            
    DATA    ;adat memória szegmens
    
; 7szegmenses kódok táblázata
hex7seg: ; 0     1     2     3     4     5     6     7     8     9    A    b    C    d    E    F
    DB  0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f, 0x77,0x7c,0x39,0x5e,0x79,0x71


TIM_per:
        DB 0x00
times:
    DB 243, 121, 60, 30

