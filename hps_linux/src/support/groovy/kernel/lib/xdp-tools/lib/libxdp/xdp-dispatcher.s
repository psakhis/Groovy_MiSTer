	.text
	.file	"xdp-dispatcher.c"
	.globl	prog0                           # -- Begin function prog0
	.p2align	3
	.type	prog0,@function
prog0:                                  # @prog0
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB0_2
	goto LBB0_1
LBB0_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB0_3
LBB0_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB0_3
LBB0_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end0:
	.size	prog0, .Lfunc_end0-prog0
                                        # -- End function
	.globl	prog1                           # -- Begin function prog1
	.p2align	3
	.type	prog1,@function
prog1:                                  # @prog1
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB1_2
	goto LBB1_1
LBB1_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB1_3
LBB1_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB1_3
LBB1_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end1:
	.size	prog1, .Lfunc_end1-prog1
                                        # -- End function
	.globl	prog2                           # -- Begin function prog2
	.p2align	3
	.type	prog2,@function
prog2:                                  # @prog2
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB2_2
	goto LBB2_1
LBB2_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB2_3
LBB2_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB2_3
LBB2_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end2:
	.size	prog2, .Lfunc_end2-prog2
                                        # -- End function
	.globl	prog3                           # -- Begin function prog3
	.p2align	3
	.type	prog3,@function
prog3:                                  # @prog3
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB3_2
	goto LBB3_1
LBB3_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB3_3
LBB3_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB3_3
LBB3_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end3:
	.size	prog3, .Lfunc_end3-prog3
                                        # -- End function
	.globl	prog4                           # -- Begin function prog4
	.p2align	3
	.type	prog4,@function
prog4:                                  # @prog4
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB4_2
	goto LBB4_1
LBB4_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB4_3
LBB4_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB4_3
LBB4_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end4:
	.size	prog4, .Lfunc_end4-prog4
                                        # -- End function
	.globl	prog5                           # -- Begin function prog5
	.p2align	3
	.type	prog5,@function
prog5:                                  # @prog5
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB5_2
	goto LBB5_1
LBB5_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB5_3
LBB5_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB5_3
LBB5_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end5:
	.size	prog5, .Lfunc_end5-prog5
                                        # -- End function
	.globl	prog6                           # -- Begin function prog6
	.p2align	3
	.type	prog6,@function
prog6:                                  # @prog6
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB6_2
	goto LBB6_1
LBB6_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB6_3
LBB6_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB6_3
LBB6_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end6:
	.size	prog6, .Lfunc_end6-prog6
                                        # -- End function
	.globl	prog7                           # -- Begin function prog7
	.p2align	3
	.type	prog7,@function
prog7:                                  # @prog7
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB7_2
	goto LBB7_1
LBB7_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB7_3
LBB7_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB7_3
LBB7_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end7:
	.size	prog7, .Lfunc_end7-prog7
                                        # -- End function
	.globl	prog8                           # -- Begin function prog8
	.p2align	3
	.type	prog8,@function
prog8:                                  # @prog8
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB8_2
	goto LBB8_1
LBB8_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB8_3
LBB8_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB8_3
LBB8_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end8:
	.size	prog8, .Lfunc_end8-prog8
                                        # -- End function
	.globl	prog9                           # -- Begin function prog9
	.p2align	3
	.type	prog9,@function
prog9:                                  # @prog9
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB9_2
	goto LBB9_1
LBB9_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB9_3
LBB9_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB9_3
LBB9_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end9:
	.size	prog9, .Lfunc_end9-prog9
                                        # -- End function
	.globl	compat_test                     # -- Begin function compat_test
	.p2align	3
	.type	compat_test,@function
compat_test:                            # @compat_test
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = 31
	*(u32 *)(r10 - 20) = r1
	r1 = *(u64 *)(r10 - 16)
	if r1 != 0 goto LBB10_2
	goto LBB10_1
LBB10_1:
	r1 = 0
	*(u32 *)(r10 - 4) = r1
	goto LBB10_3
LBB10_2:
	r1 = *(u32 *)(r10 - 20)
	*(u32 *)(r10 - 4) = r1
	goto LBB10_3
LBB10_3:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end10:
	.size	compat_test, .Lfunc_end10-compat_test
                                        # -- End function
	.section	xdp,"ax",@progbits
	.globl	xdp_dispatcher                  # -- Begin function xdp_dispatcher
	.p2align	3
	.type	xdp_dispatcher,@function
xdp_dispatcher:                         # @xdp_dispatcher
# %bb.0:
	*(u64 *)(r10 - 16) = r1
	r1 = conf ll
	r1 = *(u8 *)(r1 + 2)
	*(u8 *)(r10 - 17) = r1
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 0 goto LBB11_2
	goto LBB11_1
LBB11_1:
	goto LBB11_43
LBB11_2:
	r1 = *(u64 *)(r10 - 16)
	call prog0
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 4)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_4
	goto LBB11_3
LBB11_3:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_4:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 1 goto LBB11_6
	goto LBB11_5
LBB11_5:
	goto LBB11_43
LBB11_6:
	r1 = *(u64 *)(r10 - 16)
	call prog1
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 8)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_8
	goto LBB11_7
LBB11_7:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_8:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 2 goto LBB11_10
	goto LBB11_9
LBB11_9:
	goto LBB11_43
LBB11_10:
	r1 = *(u64 *)(r10 - 16)
	call prog2
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 12)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_12
	goto LBB11_11
LBB11_11:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_12:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 3 goto LBB11_14
	goto LBB11_13
LBB11_13:
	goto LBB11_43
LBB11_14:
	r1 = *(u64 *)(r10 - 16)
	call prog3
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 16)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_16
	goto LBB11_15
LBB11_15:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_16:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 4 goto LBB11_18
	goto LBB11_17
LBB11_17:
	goto LBB11_43
LBB11_18:
	r1 = *(u64 *)(r10 - 16)
	call prog4
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 20)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_20
	goto LBB11_19
LBB11_19:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_20:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 5 goto LBB11_22
	goto LBB11_21
LBB11_21:
	goto LBB11_43
LBB11_22:
	r1 = *(u64 *)(r10 - 16)
	call prog5
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 24)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_24
	goto LBB11_23
LBB11_23:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_24:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 6 goto LBB11_26
	goto LBB11_25
LBB11_25:
	goto LBB11_43
LBB11_26:
	r1 = *(u64 *)(r10 - 16)
	call prog6
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 28)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_28
	goto LBB11_27
LBB11_27:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_28:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 7 goto LBB11_30
	goto LBB11_29
LBB11_29:
	goto LBB11_43
LBB11_30:
	r1 = *(u64 *)(r10 - 16)
	call prog7
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 32)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_32
	goto LBB11_31
LBB11_31:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_32:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 8 goto LBB11_34
	goto LBB11_33
LBB11_33:
	goto LBB11_43
LBB11_34:
	r1 = *(u64 *)(r10 - 16)
	call prog8
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 36)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_36
	goto LBB11_35
LBB11_35:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_36:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 9 goto LBB11_38
	goto LBB11_37
LBB11_37:
	goto LBB11_43
LBB11_38:
	r1 = *(u64 *)(r10 - 16)
	call prog9
	*(u32 *)(r10 - 24) = r0
	r2 = *(u32 *)(r10 - 24)
	r1 = conf ll
	r1 = *(u32 *)(r1 + 40)
	r1 >>= r2
	r1 &= 1
	if r1 != 0 goto LBB11_40
	goto LBB11_39
LBB11_39:
	r1 = *(u32 *)(r10 - 24)
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_40:
	r1 = *(u8 *)(r10 - 17)
	if r1 s> 10 goto LBB11_42
	goto LBB11_41
LBB11_41:
	goto LBB11_43
LBB11_42:
	r1 = *(u64 *)(r10 - 16)
	call compat_test
	*(u32 *)(r10 - 24) = r0
	goto LBB11_43
LBB11_43:
	r1 = 2
	*(u32 *)(r10 - 4) = r1
	goto LBB11_44
LBB11_44:
	r0 = *(u32 *)(r10 - 4)
	exit
.Lfunc_end11:
	.size	xdp_dispatcher, .Lfunc_end11-xdp_dispatcher
                                        # -- End function
	.globl	xdp_pass                        # -- Begin function xdp_pass
	.p2align	3
	.type	xdp_pass,@function
xdp_pass:                               # @xdp_pass
# %bb.0:
	*(u64 *)(r10 - 8) = r1
	r0 = 2
	exit
.Lfunc_end12:
	.size	xdp_pass, .Lfunc_end12-xdp_pass
                                        # -- End function
	.type	conf,@object                    # @conf
	.section	.rodata,"a",@progbits
	.p2align	2
conf:
	.zero	124
	.size	conf, 124

	.type	_license,@object                # @_license
	.section	license,"aw",@progbits
	.globl	_license
_license:
	.asciz	"GPL"
	.size	_license, 4

	.type	dispatcher_version,@object      # @dispatcher_version
	.section	xdp_metadata,"aw",@progbits
	.globl	dispatcher_version
	.p2align	3
dispatcher_version:
	.quad	0
	.size	dispatcher_version, 8

	.addrsig
	.addrsig_sym prog0
	.addrsig_sym prog1
	.addrsig_sym prog2
	.addrsig_sym prog3
	.addrsig_sym prog4
	.addrsig_sym prog5
	.addrsig_sym prog6
	.addrsig_sym prog7
	.addrsig_sym prog8
	.addrsig_sym prog9
	.addrsig_sym compat_test
	.addrsig_sym xdp_dispatcher
	.addrsig_sym xdp_pass
	.addrsig_sym conf
	.addrsig_sym _license
	.addrsig_sym dispatcher_version
