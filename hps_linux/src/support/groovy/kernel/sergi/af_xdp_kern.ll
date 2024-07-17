; ModuleID = 'af_xdp_kern.c'
source_filename = "af_xdp_kern.c"
target datalayout = "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
target triple = "armv6kz-v7a-linux-gnueabihf"

%struct.anon = type { ptr, ptr, ptr, ptr }
%struct.xdp_md = type { i32, i32, i32, i32, i32 }
%struct.ethhdr = type { [6 x i8], [6 x i8], i16 }
%struct.udphdr = type { i16, i16, i16, i16 }

@xsks_map = dso_local global %struct.anon zeroinitializer, section ".maps", align 4, !dbg !0
@_license = dso_local global [4 x i8] c"GPL\00", section "license", align 1, !dbg !62
@llvm.compiler.used = appending global [3 x ptr] [ptr @_license, ptr @xdp_sock_prog, ptr @xsks_map], section "llvm.metadata"

; Function Attrs: nounwind
define dso_local i32 @xdp_sock_prog(ptr nocapture noundef readonly %0) #0 section "xdp_groovymister" !dbg !107 {
  %2 = alloca i32, align 4
  call void @llvm.dbg.value(metadata ptr %0, metadata !119, metadata !DIExpression()), !dbg !203
  call void @llvm.lifetime.start.p0(i64 4, ptr nonnull %2) #3, !dbg !204
  %3 = getelementptr inbounds %struct.xdp_md, ptr %0, i32 0, i32 4, !dbg !205
  %4 = load i32, ptr %3, align 4, !dbg !205, !tbaa !206
  call void @llvm.dbg.value(metadata i32 %4, metadata !120, metadata !DIExpression()), !dbg !203
  store i32 %4, ptr %2, align 4, !dbg !211, !tbaa !212
  %5 = load i32, ptr %0, align 4, !dbg !213, !tbaa !214
  %6 = inttoptr i32 %5 to ptr, !dbg !215
  call void @llvm.dbg.value(metadata ptr %6, metadata !201, metadata !DIExpression()), !dbg !203
  %7 = getelementptr inbounds %struct.xdp_md, ptr %0, i32 0, i32 1, !dbg !216
  %8 = load i32, ptr %7, align 4, !dbg !216, !tbaa !217
  %9 = inttoptr i32 %8 to ptr, !dbg !218
  call void @llvm.dbg.value(metadata ptr %9, metadata !202, metadata !DIExpression()), !dbg !203
  call void @llvm.dbg.value(metadata ptr undef, metadata !219, metadata !DIExpression()), !dbg !232
  call void @llvm.dbg.value(metadata ptr %6, metadata !225, metadata !DIExpression()), !dbg !232
  call void @llvm.dbg.value(metadata ptr %9, metadata !226, metadata !DIExpression()), !dbg !232
  call void @llvm.dbg.value(metadata ptr %6, metadata !227, metadata !DIExpression()), !dbg !232
  %10 = getelementptr %struct.ethhdr, ptr %6, i32 1, !dbg !235
  %11 = icmp ugt ptr %10, %9, !dbg !235
  br i1 %11, label %52, label %12, !dbg !237

12:                                               ; preds = %1
  %13 = getelementptr inbounds %struct.ethhdr, ptr %6, i32 0, i32 2, !dbg !238
  call void @llvm.dbg.value(metadata ptr %13, metadata !231, metadata !DIExpression()), !dbg !232
  %14 = load i8, ptr %13, align 1, !dbg !239, !tbaa !241
  %15 = icmp eq i8 %14, 8, !dbg !242
  br i1 %15, label %20, label %16, !dbg !243

16:                                               ; preds = %12
  %17 = getelementptr inbounds i8, ptr %6, i32 13, !dbg !244
  %18 = load i8, ptr %17, align 1, !dbg !244, !tbaa !241
  %19 = icmp eq i8 %18, 0, !dbg !245
  br i1 %19, label %20, label %52, !dbg !246

20:                                               ; preds = %16, %12
  call void @llvm.dbg.value(metadata ptr %10, metadata !228, metadata !DIExpression()), !dbg !232
  %21 = getelementptr i8, ptr %6, i32 34, !dbg !247
  %22 = icmp ugt ptr %21, %9, !dbg !247
  br i1 %22, label %52, label %23, !dbg !250

23:                                               ; preds = %20
  %24 = getelementptr i8, ptr %6, i32 23, !dbg !251
  %25 = load i8, ptr %24, align 1, !dbg !251, !tbaa !253
  %26 = icmp eq i8 %25, 17, !dbg !256
  br i1 %26, label %27, label %52, !dbg !257

27:                                               ; preds = %23
  %28 = load i8, ptr %10, align 4, !dbg !258
  %29 = and i8 %28, 15, !dbg !258
  %30 = icmp eq i8 %29, 5, !dbg !260
  br i1 %30, label %37, label %31, !dbg !261

31:                                               ; preds = %27
  %32 = shl nuw nsw i8 %29, 2, !dbg !262
  %33 = zext i8 %32 to i32, !dbg !262
  %34 = getelementptr i8, ptr %10, i32 %33, !dbg !264
  call void @llvm.dbg.value(metadata ptr %34, metadata !230, metadata !DIExpression()), !dbg !232
  %35 = getelementptr inbounds %struct.udphdr, ptr %34, i32 1, !dbg !265
  %36 = icmp ugt ptr %35, %9, !dbg !267
  br i1 %36, label %52, label %37, !dbg !268

37:                                               ; preds = %31, %27
  %38 = phi ptr [ %34, %31 ], [ %21, %27 ], !dbg !269
  call void @llvm.dbg.value(metadata ptr %38, metadata !230, metadata !DIExpression()), !dbg !232
  %39 = getelementptr inbounds %struct.udphdr, ptr %38, i32 1, !dbg !270
  %40 = icmp ugt ptr %39, %9, !dbg !270
  br i1 %40, label %52, label %41, !dbg !272

41:                                               ; preds = %37
  call void @llvm.dbg.value(metadata i32 2, metadata !121, metadata !DIExpression(DW_OP_LLVM_fragment, 0, 32)), !dbg !203
  call void @llvm.dbg.value(metadata ptr %6, metadata !121, metadata !DIExpression(DW_OP_LLVM_fragment, 32, 32)), !dbg !203
  call void @llvm.dbg.value(metadata ptr %10, metadata !121, metadata !DIExpression(DW_OP_LLVM_fragment, 64, 32)), !dbg !203
  call void @llvm.dbg.value(metadata ptr %38, metadata !121, metadata !DIExpression(DW_OP_LLVM_fragment, 96, 32)), !dbg !203
  call void @llvm.dbg.value(metadata i32 2, metadata !273, metadata !DIExpression(DW_OP_LLVM_fragment, 0, 32)), !dbg !279
  call void @llvm.dbg.value(metadata i32 undef, metadata !273, metadata !DIExpression(DW_OP_LLVM_fragment, 32, 32)), !dbg !279
  call void @llvm.dbg.value(metadata i32 undef, metadata !273, metadata !DIExpression(DW_OP_LLVM_fragment, 64, 32)), !dbg !279
  call void @llvm.dbg.value(metadata ptr %38, metadata !273, metadata !DIExpression(DW_OP_LLVM_fragment, 96, 32)), !dbg !279
  %42 = getelementptr inbounds %struct.udphdr, ptr %38, i32 0, i32 1, !dbg !282
  %43 = load i16, ptr %42, align 2, !dbg !282, !tbaa !285
  %44 = and i16 %43, -257, !dbg !287
  %45 = icmp eq i16 %44, 25725, !dbg !287
  br i1 %45, label %46, label %52, !dbg !288

46:                                               ; preds = %41
  call void @llvm.dbg.value(metadata ptr %2, metadata !120, metadata !DIExpression(DW_OP_deref)), !dbg !203
  %47 = call ptr inttoptr (i32 1 to ptr)(ptr noundef nonnull @xsks_map, ptr noundef nonnull %2) #3, !dbg !289
  %48 = icmp eq ptr %47, null, !dbg !289
  br i1 %48, label %52, label %49, !dbg !291

49:                                               ; preds = %46
  %50 = load i32, ptr %2, align 4, !dbg !292, !tbaa !212
  call void @llvm.dbg.value(metadata i32 %50, metadata !120, metadata !DIExpression()), !dbg !203
  %51 = call i32 inttoptr (i32 51 to ptr)(ptr noundef nonnull @xsks_map, i32 noundef %50, i64 noundef 0) #3, !dbg !294
  br label %52, !dbg !295

52:                                               ; preds = %16, %37, %31, %23, %20, %1, %46, %41, %49
  %53 = phi i32 [ %51, %49 ], [ 2, %41 ], [ 2, %46 ], [ 2, %1 ], [ 2, %20 ], [ 2, %23 ], [ 2, %31 ], [ 2, %37 ], [ 2, %16 ], !dbg !203
  call void @llvm.lifetime.end.p0(i64 4, ptr nonnull %2) #3, !dbg !296
  ret i32 %53, !dbg !296
}

; Function Attrs: argmemonly mustprogress nocallback nofree nosync nounwind willreturn
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #1

; Function Attrs: argmemonly mustprogress nocallback nofree nosync nounwind willreturn
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #1

; Function Attrs: nocallback nofree nosync nounwind readnone speculatable willreturn
declare void @llvm.dbg.value(metadata, metadata, metadata) #2

attributes #0 = { nounwind "frame-pointer"="none" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="arm1176jzf-s" "target-features"="+armv6kz,+dsp,+fp64,+strict-align,+vfp2,+vfp2sp,-aes,-d32,-fp-armv8,-fp-armv8d16,-fp-armv8d16sp,-fp-armv8sp,-fp16,-fp16fml,-fullfp16,-neon,-sha2,-thumb-mode,-vfp3,-vfp3d16,-vfp3d16sp,-vfp3sp,-vfp4,-vfp4d16,-vfp4d16sp,-vfp4sp" }
attributes #1 = { argmemonly mustprogress nocallback nofree nosync nounwind willreturn }
attributes #2 = { nocallback nofree nosync nounwind readnone speculatable willreturn }
attributes #3 = { nounwind }

!llvm.dbg.cu = !{!2}
!llvm.module.flags = !{!100, !101, !102, !103, !104, !105}
!llvm.ident = !{!106}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(name: "xsks_map", scope: !2, file: !3, line: 29, type: !84, isLocal: false, isDefinition: true)
!2 = distinct !DICompileUnit(language: DW_LANG_C99, file: !3, producer: "clang version 15.0.3", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, enums: !4, retainedTypes: !43, globals: !61, splitDebugInlining: false, nameTableKind: None)
!3 = !DIFile(filename: "af_xdp_kern.c", directory: "C:/msys_mister/home/Recreativa/kernel/sergi", checksumkind: CSK_MD5, checksum: "a00971b9d98c56821e6208df6ec25cd1")
!4 = !{!5, !14}
!5 = !DICompositeType(tag: DW_TAG_enumeration_type, name: "xdp_action", file: !6, line: 2563, baseType: !7, size: 32, elements: !8)
!6 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/bpf.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "be0b8a4cc8532fbae80d3578e0f7df4c")
!7 = !DIBasicType(name: "unsigned int", size: 32, encoding: DW_ATE_unsigned)
!8 = !{!9, !10, !11, !12, !13}
!9 = !DIEnumerator(name: "XDP_ABORTED", value: 0)
!10 = !DIEnumerator(name: "XDP_DROP", value: 1)
!11 = !DIEnumerator(name: "XDP_PASS", value: 2)
!12 = !DIEnumerator(name: "XDP_TX", value: 3)
!13 = !DIEnumerator(name: "XDP_REDIRECT", value: 4)
!14 = !DICompositeType(tag: DW_TAG_enumeration_type, file: !15, line: 40, baseType: !7, size: 32, elements: !16)
!15 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/netinet/in.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "6a5254a491bcdb8c3253de75bf3571c1")
!16 = !{!17, !18, !19, !20, !21, !22, !23, !24, !25, !26, !27, !28, !29, !30, !31, !32, !33, !34, !35, !36, !37, !38, !39, !40, !41, !42}
!17 = !DIEnumerator(name: "IPPROTO_IP", value: 0)
!18 = !DIEnumerator(name: "IPPROTO_ICMP", value: 1)
!19 = !DIEnumerator(name: "IPPROTO_IGMP", value: 2)
!20 = !DIEnumerator(name: "IPPROTO_IPIP", value: 4)
!21 = !DIEnumerator(name: "IPPROTO_TCP", value: 6)
!22 = !DIEnumerator(name: "IPPROTO_EGP", value: 8)
!23 = !DIEnumerator(name: "IPPROTO_PUP", value: 12)
!24 = !DIEnumerator(name: "IPPROTO_UDP", value: 17)
!25 = !DIEnumerator(name: "IPPROTO_IDP", value: 22)
!26 = !DIEnumerator(name: "IPPROTO_TP", value: 29)
!27 = !DIEnumerator(name: "IPPROTO_DCCP", value: 33)
!28 = !DIEnumerator(name: "IPPROTO_IPV6", value: 41)
!29 = !DIEnumerator(name: "IPPROTO_RSVP", value: 46)
!30 = !DIEnumerator(name: "IPPROTO_GRE", value: 47)
!31 = !DIEnumerator(name: "IPPROTO_ESP", value: 50)
!32 = !DIEnumerator(name: "IPPROTO_AH", value: 51)
!33 = !DIEnumerator(name: "IPPROTO_MTP", value: 92)
!34 = !DIEnumerator(name: "IPPROTO_BEETPH", value: 94)
!35 = !DIEnumerator(name: "IPPROTO_ENCAP", value: 98)
!36 = !DIEnumerator(name: "IPPROTO_PIM", value: 103)
!37 = !DIEnumerator(name: "IPPROTO_COMP", value: 108)
!38 = !DIEnumerator(name: "IPPROTO_SCTP", value: 132)
!39 = !DIEnumerator(name: "IPPROTO_UDPLITE", value: 136)
!40 = !DIEnumerator(name: "IPPROTO_MPLS", value: 137)
!41 = !DIEnumerator(name: "IPPROTO_RAW", value: 255)
!42 = !DIEnumerator(name: "IPPROTO_MAX", value: 256)
!43 = !{!44, !45, !46, !50, !58}
!44 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 32)
!45 = !DIBasicType(name: "long", size: 32, encoding: DW_ATE_signed)
!46 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !47, size: 32)
!47 = !DIDerivedType(tag: DW_TAG_typedef, name: "u8", file: !48, line: 13, baseType: !49)
!48 = !DIFile(filename: "./ip6.h", directory: "C:/msys_mister/home/Recreativa/kernel/sergi", checksumkind: CSK_MD5, checksum: "ead9f2b23475dfebbdf81fcba535b22b")
!49 = !DIBasicType(name: "unsigned char", size: 8, encoding: DW_ATE_unsigned_char)
!50 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !51, size: 32)
!51 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "ipv6_opt_hdr", file: !52, line: 61, size: 16, elements: !53)
!52 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/ipv6.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "e55b259c22016dcf256944ee184ef47c")
!53 = !{!54, !57}
!54 = !DIDerivedType(tag: DW_TAG_member, name: "nexthdr", scope: !51, file: !52, line: 62, baseType: !55, size: 8)
!55 = !DIDerivedType(tag: DW_TAG_typedef, name: "__u8", file: !56, line: 21, baseType: !49)
!56 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/asm-generic/int-ll64.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "b810f270733e106319b67ef512c6246e")
!57 = !DIDerivedType(tag: DW_TAG_member, name: "hdrlen", scope: !51, file: !52, line: 63, baseType: !55, size: 8, offset: 8)
!58 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint16_t", file: !59, line: 40, baseType: !60)
!59 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/bits/types.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "f6304b1a6dcfc6bee76e9a51043b5090")
!60 = !DIBasicType(name: "unsigned short", size: 16, encoding: DW_ATE_unsigned)
!61 = !{!62, !0, !68, !76}
!62 = !DIGlobalVariableExpression(var: !63, expr: !DIExpression())
!63 = distinct !DIGlobalVariable(name: "_license", scope: !2, file: !3, line: 96, type: !64, isLocal: false, isDefinition: true)
!64 = !DICompositeType(tag: DW_TAG_array_type, baseType: !65, size: 32, elements: !66)
!65 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_unsigned_char)
!66 = !{!67}
!67 = !DISubrange(count: 4)
!68 = !DIGlobalVariableExpression(var: !69, expr: !DIExpression())
!69 = distinct !DIGlobalVariable(name: "bpf_map_lookup_elem", scope: !2, file: !70, line: 51, type: !71, isLocal: true, isDefinition: true)
!70 = !DIFile(filename: "../lib/libbpf/bpf/bpf_helper_defs.h", directory: "C:/msys_mister/home/Recreativa/kernel/sergi", checksumkind: CSK_MD5, checksum: "dfd08b245d3237405b68f7047920fa68")
!71 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !72, size: 32)
!72 = !DISubroutineType(types: !73)
!73 = !{!44, !44, !74}
!74 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !75, size: 32)
!75 = !DIDerivedType(tag: DW_TAG_const_type, baseType: null)
!76 = !DIGlobalVariableExpression(var: !77, expr: !DIExpression())
!77 = distinct !DIGlobalVariable(name: "bpf_redirect_map", scope: !2, file: !70, line: 1302, type: !78, isLocal: true, isDefinition: true)
!78 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !79, size: 32)
!79 = !DISubroutineType(types: !80)
!80 = !{!45, !44, !81, !82}
!81 = !DIDerivedType(tag: DW_TAG_typedef, name: "__u32", file: !56, line: 27, baseType: !7)
!82 = !DIDerivedType(tag: DW_TAG_typedef, name: "__u64", file: !56, line: 31, baseType: !83)
!83 = !DIBasicType(name: "unsigned long long", size: 64, encoding: DW_ATE_unsigned)
!84 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !3, line: 24, size: 128, elements: !85)
!85 = !{!86, !92, !94, !95}
!86 = !DIDerivedType(tag: DW_TAG_member, name: "type", scope: !84, file: !3, line: 25, baseType: !87, size: 32)
!87 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !88, size: 32)
!88 = !DICompositeType(tag: DW_TAG_array_type, baseType: !89, size: 544, elements: !90)
!89 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!90 = !{!91}
!91 = !DISubrange(count: 17)
!92 = !DIDerivedType(tag: DW_TAG_member, name: "key", scope: !84, file: !3, line: 26, baseType: !93, size: 32, offset: 32)
!93 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !81, size: 32)
!94 = !DIDerivedType(tag: DW_TAG_member, name: "value", scope: !84, file: !3, line: 27, baseType: !93, size: 32, offset: 64)
!95 = !DIDerivedType(tag: DW_TAG_member, name: "max_entries", scope: !84, file: !3, line: 28, baseType: !96, size: 32, offset: 96)
!96 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !97, size: 32)
!97 = !DICompositeType(tag: DW_TAG_array_type, baseType: !89, size: 32, elements: !98)
!98 = !{!99}
!99 = !DISubrange(count: 1)
!100 = !{i32 7, !"Dwarf Version", i32 5}
!101 = !{i32 2, !"Debug Info Version", i32 3}
!102 = !{i32 1, !"wchar_size", i32 4}
!103 = !{i32 1, !"min_enum_size", i32 4}
!104 = !{i32 7, !"PIC Level", i32 2}
!105 = !{i32 7, !"PIE Level", i32 2}
!106 = !{!"clang version 15.0.3"}
!107 = distinct !DISubprogram(name: "xdp_sock_prog", scope: !3, file: !3, line: 53, type: !108, scopeLine: 54, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !2, retainedNodes: !118)
!108 = !DISubroutineType(types: !109)
!109 = !{!89, !110}
!110 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !111, size: 32)
!111 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "xdp_md", file: !6, line: 2574, size: 160, elements: !112)
!112 = !{!113, !114, !115, !116, !117}
!113 = !DIDerivedType(tag: DW_TAG_member, name: "data", scope: !111, file: !6, line: 2575, baseType: !81, size: 32)
!114 = !DIDerivedType(tag: DW_TAG_member, name: "data_end", scope: !111, file: !6, line: 2576, baseType: !81, size: 32, offset: 32)
!115 = !DIDerivedType(tag: DW_TAG_member, name: "data_meta", scope: !111, file: !6, line: 2577, baseType: !81, size: 32, offset: 64)
!116 = !DIDerivedType(tag: DW_TAG_member, name: "ingress_ifindex", scope: !111, file: !6, line: 2579, baseType: !81, size: 32, offset: 96)
!117 = !DIDerivedType(tag: DW_TAG_member, name: "rx_queue_index", scope: !111, file: !6, line: 2580, baseType: !81, size: 32, offset: 128)
!118 = !{!119, !120, !121, !201, !202}
!119 = !DILocalVariable(name: "ctx", arg: 1, scope: !107, file: !3, line: 53, type: !110)
!120 = !DILocalVariable(name: "index", scope: !107, file: !3, line: 55, type: !89)
!121 = !DILocalVariable(name: "hdrs", scope: !107, file: !3, line: 57, type: !122)
!122 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "pkthdrs", file: !123, line: 7, size: 128, elements: !124)
!123 = !DIFile(filename: "./packet_parse.h", directory: "C:/msys_mister/home/Recreativa/kernel/sergi", checksumkind: CSK_MD5, checksum: "a74a8ce7efb733ac4d658dc5e24c17a2")
!124 = !{!125, !126, !140, !192}
!125 = !DIDerivedType(tag: DW_TAG_member, name: "family", scope: !122, file: !123, line: 8, baseType: !89, size: 32)
!126 = !DIDerivedType(tag: DW_TAG_member, name: "eth", scope: !122, file: !123, line: 9, baseType: !127, size: 32, offset: 32)
!127 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !128, size: 32)
!128 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "ethhdr", file: !129, line: 161, size: 112, elements: !130)
!129 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/if_ether.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "bcc54338453990395c6aa681d71b94d5")
!130 = !{!131, !135, !136}
!131 = !DIDerivedType(tag: DW_TAG_member, name: "h_dest", scope: !128, file: !129, line: 162, baseType: !132, size: 48)
!132 = !DICompositeType(tag: DW_TAG_array_type, baseType: !49, size: 48, elements: !133)
!133 = !{!134}
!134 = !DISubrange(count: 6)
!135 = !DIDerivedType(tag: DW_TAG_member, name: "h_source", scope: !128, file: !129, line: 163, baseType: !132, size: 48, offset: 48)
!136 = !DIDerivedType(tag: DW_TAG_member, name: "h_proto", scope: !128, file: !129, line: 164, baseType: !137, size: 16, offset: 96)
!137 = !DIDerivedType(tag: DW_TAG_typedef, name: "__be16", file: !138, line: 25, baseType: !139)
!138 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/types.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "52ec79a38e49ac7d1dc9e146ba88a7b1")
!139 = !DIDerivedType(tag: DW_TAG_typedef, name: "__u16", file: !56, line: 24, baseType: !60)
!140 = !DIDerivedType(tag: DW_TAG_member, scope: !122, file: !123, line: 10, baseType: !141, size: 32, offset: 64)
!141 = distinct !DICompositeType(tag: DW_TAG_union_type, scope: !122, file: !123, line: 10, size: 32, elements: !142)
!142 = !{!143, !161}
!143 = !DIDerivedType(tag: DW_TAG_member, name: "iph", scope: !141, file: !123, line: 11, baseType: !144, size: 32)
!144 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !145, size: 32)
!145 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "iphdr", file: !146, line: 86, size: 160, elements: !147)
!146 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/ip.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "8776158f5e307e9a8189f0dae4b43df4")
!147 = !{!148, !149, !150, !151, !152, !153, !154, !155, !156, !158, !160}
!148 = !DIDerivedType(tag: DW_TAG_member, name: "ihl", scope: !145, file: !146, line: 88, baseType: !55, size: 4, flags: DIFlagBitField, extraData: i64 0)
!149 = !DIDerivedType(tag: DW_TAG_member, name: "version", scope: !145, file: !146, line: 89, baseType: !55, size: 4, offset: 4, flags: DIFlagBitField, extraData: i64 0)
!150 = !DIDerivedType(tag: DW_TAG_member, name: "tos", scope: !145, file: !146, line: 96, baseType: !55, size: 8, offset: 8)
!151 = !DIDerivedType(tag: DW_TAG_member, name: "tot_len", scope: !145, file: !146, line: 97, baseType: !137, size: 16, offset: 16)
!152 = !DIDerivedType(tag: DW_TAG_member, name: "id", scope: !145, file: !146, line: 98, baseType: !137, size: 16, offset: 32)
!153 = !DIDerivedType(tag: DW_TAG_member, name: "frag_off", scope: !145, file: !146, line: 99, baseType: !137, size: 16, offset: 48)
!154 = !DIDerivedType(tag: DW_TAG_member, name: "ttl", scope: !145, file: !146, line: 100, baseType: !55, size: 8, offset: 64)
!155 = !DIDerivedType(tag: DW_TAG_member, name: "protocol", scope: !145, file: !146, line: 101, baseType: !55, size: 8, offset: 72)
!156 = !DIDerivedType(tag: DW_TAG_member, name: "check", scope: !145, file: !146, line: 102, baseType: !157, size: 16, offset: 80)
!157 = !DIDerivedType(tag: DW_TAG_typedef, name: "__sum16", file: !138, line: 31, baseType: !139)
!158 = !DIDerivedType(tag: DW_TAG_member, name: "saddr", scope: !145, file: !146, line: 103, baseType: !159, size: 32, offset: 96)
!159 = !DIDerivedType(tag: DW_TAG_typedef, name: "__be32", file: !138, line: 27, baseType: !81)
!160 = !DIDerivedType(tag: DW_TAG_member, name: "daddr", scope: !145, file: !146, line: 104, baseType: !159, size: 32, offset: 128)
!161 = !DIDerivedType(tag: DW_TAG_member, name: "iph6", scope: !141, file: !123, line: 12, baseType: !162, size: 32)
!162 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !163, size: 32)
!163 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "ipv6hdr", file: !52, line: 116, size: 320, elements: !164)
!164 = !{!165, !166, !167, !171, !172, !173, !174, !191}
!165 = !DIDerivedType(tag: DW_TAG_member, name: "priority", scope: !163, file: !52, line: 118, baseType: !55, size: 4, flags: DIFlagBitField, extraData: i64 0)
!166 = !DIDerivedType(tag: DW_TAG_member, name: "version", scope: !163, file: !52, line: 119, baseType: !55, size: 4, offset: 4, flags: DIFlagBitField, extraData: i64 0)
!167 = !DIDerivedType(tag: DW_TAG_member, name: "flow_lbl", scope: !163, file: !52, line: 126, baseType: !168, size: 24, offset: 8)
!168 = !DICompositeType(tag: DW_TAG_array_type, baseType: !55, size: 24, elements: !169)
!169 = !{!170}
!170 = !DISubrange(count: 3)
!171 = !DIDerivedType(tag: DW_TAG_member, name: "payload_len", scope: !163, file: !52, line: 128, baseType: !137, size: 16, offset: 32)
!172 = !DIDerivedType(tag: DW_TAG_member, name: "nexthdr", scope: !163, file: !52, line: 129, baseType: !55, size: 8, offset: 48)
!173 = !DIDerivedType(tag: DW_TAG_member, name: "hop_limit", scope: !163, file: !52, line: 130, baseType: !55, size: 8, offset: 56)
!174 = !DIDerivedType(tag: DW_TAG_member, name: "saddr", scope: !163, file: !52, line: 132, baseType: !175, size: 128, offset: 64)
!175 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "in6_addr", file: !176, line: 33, size: 128, elements: !177)
!176 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/in6.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "6890b52e3b224d2ecabb87982fec0e1e")
!177 = !{!178}
!178 = !DIDerivedType(tag: DW_TAG_member, name: "in6_u", scope: !175, file: !176, line: 40, baseType: !179, size: 128)
!179 = distinct !DICompositeType(tag: DW_TAG_union_type, scope: !175, file: !176, line: 34, size: 128, elements: !180)
!180 = !{!181, !185, !189}
!181 = !DIDerivedType(tag: DW_TAG_member, name: "u6_addr8", scope: !179, file: !176, line: 35, baseType: !182, size: 128)
!182 = !DICompositeType(tag: DW_TAG_array_type, baseType: !55, size: 128, elements: !183)
!183 = !{!184}
!184 = !DISubrange(count: 16)
!185 = !DIDerivedType(tag: DW_TAG_member, name: "u6_addr16", scope: !179, file: !176, line: 37, baseType: !186, size: 128)
!186 = !DICompositeType(tag: DW_TAG_array_type, baseType: !137, size: 128, elements: !187)
!187 = !{!188}
!188 = !DISubrange(count: 8)
!189 = !DIDerivedType(tag: DW_TAG_member, name: "u6_addr32", scope: !179, file: !176, line: 38, baseType: !190, size: 128)
!190 = !DICompositeType(tag: DW_TAG_array_type, baseType: !159, size: 128, elements: !66)
!191 = !DIDerivedType(tag: DW_TAG_member, name: "daddr", scope: !163, file: !52, line: 133, baseType: !175, size: 128, offset: 192)
!192 = !DIDerivedType(tag: DW_TAG_member, name: "udp", scope: !122, file: !123, line: 14, baseType: !193, size: 32, offset: 96)
!193 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !194, size: 32)
!194 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "udphdr", file: !195, line: 23, size: 64, elements: !196)
!195 = !DIFile(filename: "opt/arm/arm-none-linux-gnueabihf/libc/usr/include/linux/udp.h", directory: "C:/msys_mister", checksumkind: CSK_MD5, checksum: "ce120e4df4c0e2a238d0f15b648376bc")
!196 = !{!197, !198, !199, !200}
!197 = !DIDerivedType(tag: DW_TAG_member, name: "source", scope: !194, file: !195, line: 24, baseType: !137, size: 16)
!198 = !DIDerivedType(tag: DW_TAG_member, name: "dest", scope: !194, file: !195, line: 25, baseType: !137, size: 16, offset: 16)
!199 = !DIDerivedType(tag: DW_TAG_member, name: "len", scope: !194, file: !195, line: 26, baseType: !137, size: 16, offset: 32)
!200 = !DIDerivedType(tag: DW_TAG_member, name: "check", scope: !194, file: !195, line: 27, baseType: !157, size: 16, offset: 48)
!201 = !DILocalVariable(name: "pkt", scope: !107, file: !3, line: 70, type: !44)
!202 = !DILocalVariable(name: "end", scope: !107, file: !3, line: 70, type: !44)
!203 = !DILocation(line: 0, scope: !107)
!204 = !DILocation(line: 55, column: 5, scope: !107)
!205 = !DILocation(line: 55, column: 22, scope: !107)
!206 = !{!207, !208, i64 16}
!207 = !{!"xdp_md", !208, i64 0, !208, i64 4, !208, i64 8, !208, i64 12, !208, i64 16}
!208 = !{!"int", !209, i64 0}
!209 = !{!"omnipotent char", !210, i64 0}
!210 = !{!"Simple C/C++ TBAA"}
!211 = !DILocation(line: 55, column: 9, scope: !107)
!212 = !{!208, !208, i64 0}
!213 = !DILocation(line: 71, column: 30, scope: !107)
!214 = !{!207, !208, i64 0}
!215 = !DILocation(line: 71, column: 11, scope: !107)
!216 = !DILocation(line: 72, column: 30, scope: !107)
!217 = !{!207, !208, i64 4}
!218 = !DILocation(line: 72, column: 11, scope: !107)
!219 = !DILocalVariable(name: "hdrs", arg: 1, scope: !220, file: !123, line: 101, type: !223)
!220 = distinct !DISubprogram(name: "packet_parse", scope: !123, file: !123, line: 101, type: !221, scopeLine: 102, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !2, retainedNodes: !224)
!221 = !DISubroutineType(types: !222)
!222 = !{!89, !223, !44, !44}
!223 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !122, size: 32)
!224 = !{!219, !225, !226, !227, !228, !229, !230, !231}
!225 = !DILocalVariable(name: "pkt", arg: 2, scope: !220, file: !123, line: 101, type: !44)
!226 = !DILocalVariable(name: "end", arg: 3, scope: !220, file: !123, line: 101, type: !44)
!227 = !DILocalVariable(name: "eth", scope: !220, file: !123, line: 103, type: !127)
!228 = !DILocalVariable(name: "iph", scope: !220, file: !123, line: 104, type: !144)
!229 = !DILocalVariable(name: "iph6", scope: !220, file: !123, line: 105, type: !162)
!230 = !DILocalVariable(name: "udp", scope: !220, file: !123, line: 106, type: !193)
!231 = !DILocalVariable(name: "p", scope: !220, file: !123, line: 107, type: !46)
!232 = !DILocation(line: 0, scope: !220, inlinedAt: !233)
!233 = distinct !DILocation(line: 74, column: 10, scope: !234)
!234 = distinct !DILexicalBlock(scope: !107, file: !3, line: 74, column: 9)
!235 = !DILocation(line: 111, column: 7, scope: !236, inlinedAt: !233)
!236 = distinct !DILexicalBlock(scope: !220, file: !123, line: 111, column: 6)
!237 = !DILocation(line: 111, column: 6, scope: !220, inlinedAt: !233)
!238 = !DILocation(line: 114, column: 18, scope: !220, inlinedAt: !233)
!239 = !DILocation(line: 117, column: 6, scope: !240, inlinedAt: !233)
!240 = distinct !DILexicalBlock(scope: !220, file: !123, line: 117, column: 6)
!241 = !{!209, !209, i64 0}
!242 = !DILocation(line: 117, column: 11, scope: !240, inlinedAt: !233)
!243 = !DILocation(line: 117, column: 19, scope: !240, inlinedAt: !233)
!244 = !DILocation(line: 117, column: 22, scope: !240, inlinedAt: !233)
!245 = !DILocation(line: 117, column: 27, scope: !240, inlinedAt: !233)
!246 = !DILocation(line: 117, column: 6, scope: !220, inlinedAt: !233)
!247 = !DILocation(line: 119, column: 8, scope: !248, inlinedAt: !233)
!248 = distinct !DILexicalBlock(scope: !249, file: !123, line: 119, column: 7)
!249 = distinct !DILexicalBlock(scope: !240, file: !123, line: 117, column: 35)
!250 = !DILocation(line: 119, column: 7, scope: !249, inlinedAt: !233)
!251 = !DILocation(line: 122, column: 12, scope: !252, inlinedAt: !233)
!252 = distinct !DILexicalBlock(scope: !249, file: !123, line: 122, column: 7)
!253 = !{!254, !209, i64 9}
!254 = !{!"iphdr", !209, i64 0, !209, i64 0, !209, i64 1, !255, i64 2, !255, i64 4, !255, i64 6, !209, i64 8, !209, i64 9, !255, i64 10, !208, i64 12, !208, i64 16}
!255 = !{!"short", !209, i64 0}
!256 = !DILocation(line: 122, column: 21, scope: !252, inlinedAt: !233)
!257 = !DILocation(line: 122, column: 7, scope: !249, inlinedAt: !233)
!258 = !DILocation(line: 125, column: 17, scope: !259, inlinedAt: !233)
!259 = distinct !DILexicalBlock(scope: !249, file: !123, line: 125, column: 7)
!260 = !DILocation(line: 125, column: 9, scope: !259, inlinedAt: !233)
!261 = !DILocation(line: 125, column: 7, scope: !249, inlinedAt: !233)
!262 = !DILocation(line: 128, column: 33, scope: !263, inlinedAt: !233)
!263 = distinct !DILexicalBlock(scope: !259, file: !123, line: 127, column: 10)
!264 = !DILocation(line: 128, column: 21, scope: !263, inlinedAt: !233)
!265 = !DILocation(line: 130, column: 21, scope: !266, inlinedAt: !233)
!266 = distinct !DILexicalBlock(scope: !263, file: !123, line: 130, column: 8)
!267 = !DILocation(line: 130, column: 26, scope: !266, inlinedAt: !233)
!268 = !DILocation(line: 130, column: 8, scope: !263, inlinedAt: !233)
!269 = !DILocation(line: 0, scope: !259, inlinedAt: !233)
!270 = !DILocation(line: 134, column: 8, scope: !271, inlinedAt: !233)
!271 = distinct !DILexicalBlock(scope: !249, file: !123, line: 134, column: 7)
!272 = !DILocation(line: 134, column: 7, scope: !249, inlinedAt: !233)
!273 = !DILocalVariable(name: "hdrs", arg: 1, scope: !274, file: !3, line: 40, type: !122)
!274 = distinct !DISubprogram(name: "check_ipport", scope: !3, file: !3, line: 40, type: !275, scopeLine: 41, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !2, retainedNodes: !278)
!275 = !DISubroutineType(types: !276)
!276 = !{!277, !122}
!277 = !DIBasicType(name: "_Bool", size: 8, encoding: DW_ATE_boolean)
!278 = !{!273}
!279 = !DILocation(line: 0, scope: !274, inlinedAt: !280)
!280 = distinct !DILocation(line: 80, column: 10, scope: !281)
!281 = distinct !DILexicalBlock(scope: !107, file: !3, line: 80, column: 9)
!282 = !DILocation(line: 44, column: 12, scope: !283, inlinedAt: !280)
!283 = distinct !DILexicalBlock(scope: !284, file: !3, line: 43, column: 2)
!284 = distinct !DILexicalBlock(scope: !274, file: !3, line: 42, column: 6)
!285 = !{!286, !255, i64 2}
!286 = !{!"udphdr", !255, i64 0, !255, i64 2, !255, i64 4, !255, i64 6}
!287 = !DILocation(line: 44, column: 47, scope: !283, inlinedAt: !280)
!288 = !DILocation(line: 80, column: 9, scope: !107)
!289 = !DILocation(line: 87, column: 9, scope: !290)
!290 = distinct !DILexicalBlock(scope: !107, file: !3, line: 87, column: 9)
!291 = !DILocation(line: 87, column: 9, scope: !107)
!292 = !DILocation(line: 89, column: 44, scope: !293)
!293 = distinct !DILexicalBlock(scope: !290, file: !3, line: 88, column: 5)
!294 = !DILocation(line: 89, column: 16, scope: !293)
!295 = !DILocation(line: 89, column: 9, scope: !293)
!296 = !DILocation(line: 94, column: 1, scope: !107)
