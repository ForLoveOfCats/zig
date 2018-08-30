const builtin = @import("builtin");
const std = @import("index.zig");
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const warn = std.debug.warn;
const Coff = std.coff.Coff;

const ArrayList = std.ArrayList;

// https://llvm.org/docs/PDB/DbiStream.html#stream-header
const DbiStreamHeader = packed struct {
    VersionSignature: i32,
    VersionHeader: u32,
    Age: u32,
    GlobalStreamIndex: u16,
    BuildNumber: u16,
    PublicStreamIndex: u16,
    PdbDllVersion: u16,
    SymRecordStream: u16,
    PdbDllRbld: u16,
    ModInfoSize: u32,
    SectionContributionSize: u32,
    SectionMapSize: u32,
    SourceInfoSize: i32,
    TypeServerSize: i32,
    MFCTypeServerIndex: u32,
    OptionalDbgHeaderSize: i32,
    ECSubstreamSize: i32,
    Flags: u16,
    Machine: u16,
    Padding: u32,
};

const SectionContribEntry = packed struct {
    Section: u16,
    Padding1: [2]u8,
    Offset: u32,
    Size: u32,
    Characteristics: u32,
    ModuleIndex: u16,
    Padding2: [2]u8,
    DataCrc: u32,
    RelocCrc: u32,
};

const ModInfo = packed struct {
    Unused1: u32,
    SectionContr: SectionContribEntry,
    Flags: u16,
    ModuleSymStream: u16,
    SymByteSize: u32,
    C11ByteSize: u32,
    C13ByteSize: u32,
    SourceFileCount: u16,
    Padding: [2]u8,
    Unused2: u32,
    SourceFileNameIndex: u32,
    PdbFilePathNameIndex: u32,
    // These fields are variable length
    //ModuleName: char[],
    //ObjFileName: char[],
};

const SectionMapHeader = packed struct {
  Count: u16,    /// Number of segment descriptors
  LogCount: u16, /// Number of logical segment descriptors
};

const SectionMapEntry = packed struct {
  Flags: u16 ,         /// See the SectionMapEntryFlags enum below.
  Ovl: u16 ,           /// Logical overlay number
  Group: u16 ,         /// Group index into descriptor array.
  Frame: u16 ,
  SectionName: u16 ,   /// Byte index of segment / group name in string table, or 0xFFFF.
  ClassName: u16 ,     /// Byte index of class in string table, or 0xFFFF.
  Offset: u32 ,        /// Byte offset of the logical segment within physical segment.  If group is set in flags, this is the offset of the group.
  SectionLength: u32 , /// Byte count of the segment or group.
};

pub const StreamType = enum(u16) {
    Pdb = 1,
    Tpi = 2,
    Dbi = 3,
    Ipi = 4,
};

const Module = struct {
    mod_info: ModInfo,
    module_name: []u8,
    obj_file_name: []u8,
};

/// Distinguishes individual records in the Symbols subsection of a .debug$S
/// section. Equivalent to SYM_ENUM_e in cvinfo.h.
pub const SymbolRecordKind = enum(u16) {
    InlineesSym = 4456,
    ScopeEndSym = 6,
    InlineSiteEnd = 4430,
    ProcEnd = 4431,
    Thunk32Sym = 4354,
    TrampolineSym = 4396,
    SectionSym = 4406,
    CoffGroupSym = 4407,
    ExportSym = 4408,
    ProcSym = 4367,
    GlobalProcSym = 4368,
    ProcIdSym = 4422,
    GlobalProcIdSym = 4423,
    DPCProcSym = 4437,
    DPCProcIdSym = 4438,
    RegisterSym = 4358,
    PublicSym32 = 4366,
    ProcRefSym = 4389,
    LocalProcRef = 4391,
    EnvBlockSym = 4413,
    InlineSiteSym = 4429,
    LocalSym = 4414,
    DefRangeSym = 4415,
    DefRangeSubfieldSym = 4416,
    DefRangeRegisterSym = 4417,
    DefRangeFramePointerRelSym = 4418,
    DefRangeSubfieldRegisterSym = 4419,
    DefRangeFramePointerRelFullScopeSym = 4420,
    DefRangeRegisterRelSym = 4421,
    BlockSym = 4355,
    LabelSym = 4357,
    ObjNameSym = 4353,
    Compile2Sym = 4374,
    Compile3Sym = 4412,
    FrameProcSym = 4114,
    CallSiteInfoSym = 4409,
    FileStaticSym = 4435,
    HeapAllocationSiteSym = 4446,
    FrameCookieSym = 4410,
    CallerSym = 4442,
    CalleeSym = 4443,
    UDTSym = 4360,
    CobolUDT = 4361,
    BuildInfoSym = 4428,
    BPRelativeSym = 4363,
    RegRelativeSym = 4369,
    ConstantSym = 4359,
    ManagedConstant = 4397,
    DataSym = 4364,
    GlobalData = 4365,
    ManagedLocalData = 4380,
    ManagedGlobalData = 4381,
    ThreadLocalDataSym = 4370,
    GlobalTLS = 4371,
};

/// Duplicate copy of SymbolRecordKind, but using the official CV names. Useful
/// for reference purposes and when dealing with unknown record types.
pub const SymbolKind = enum(u16) {
    S_COMPILE = 1,
    S_REGISTER_16t = 2,
    S_CONSTANT_16t = 3,
    S_UDT_16t = 4,
    S_SSEARCH = 5,
    S_SKIP = 7,
    S_CVRESERVE = 8,
    S_OBJNAME_ST = 9,
    S_ENDARG = 10,
    S_COBOLUDT_16t = 11,
    S_MANYREG_16t = 12,
    S_RETURN = 13,
    S_ENTRYTHIS = 14,
    S_BPREL16 = 256,
    S_LDATA16 = 257,
    S_GDATA16 = 258,
    S_PUB16 = 259,
    S_LPROC16 = 260,
    S_GPROC16 = 261,
    S_THUNK16 = 262,
    S_BLOCK16 = 263,
    S_WITH16 = 264,
    S_LABEL16 = 265,
    S_CEXMODEL16 = 266,
    S_VFTABLE16 = 267,
    S_REGREL16 = 268,
    S_BPREL32_16t = 512,
    S_LDATA32_16t = 513,
    S_GDATA32_16t = 514,
    S_PUB32_16t = 515,
    S_LPROC32_16t = 516,
    S_GPROC32_16t = 517,
    S_THUNK32_ST = 518,
    S_BLOCK32_ST = 519,
    S_WITH32_ST = 520,
    S_LABEL32_ST = 521,
    S_CEXMODEL32 = 522,
    S_VFTABLE32_16t = 523,
    S_REGREL32_16t = 524,
    S_LTHREAD32_16t = 525,
    S_GTHREAD32_16t = 526,
    S_SLINK32 = 527,
    S_LPROCMIPS_16t = 768,
    S_GPROCMIPS_16t = 769,
    S_PROCREF_ST = 1024,
    S_DATAREF_ST = 1025,
    S_ALIGN = 1026,
    S_LPROCREF_ST = 1027,
    S_OEM = 1028,
    S_TI16_MAX = 4096,
    S_REGISTER_ST = 4097,
    S_CONSTANT_ST = 4098,
    S_UDT_ST = 4099,
    S_COBOLUDT_ST = 4100,
    S_MANYREG_ST = 4101,
    S_BPREL32_ST = 4102,
    S_LDATA32_ST = 4103,
    S_GDATA32_ST = 4104,
    S_PUB32_ST = 4105,
    S_LPROC32_ST = 4106,
    S_GPROC32_ST = 4107,
    S_VFTABLE32 = 4108,
    S_REGREL32_ST = 4109,
    S_LTHREAD32_ST = 4110,
    S_GTHREAD32_ST = 4111,
    S_LPROCMIPS_ST = 4112,
    S_GPROCMIPS_ST = 4113,
    S_COMPILE2_ST = 4115,
    S_MANYREG2_ST = 4116,
    S_LPROCIA64_ST = 4117,
    S_GPROCIA64_ST = 4118,
    S_LOCALSLOT_ST = 4119,
    S_PARAMSLOT_ST = 4120,
    S_ANNOTATION = 4121,
    S_GMANPROC_ST = 4122,
    S_LMANPROC_ST = 4123,
    S_RESERVED1 = 4124,
    S_RESERVED2 = 4125,
    S_RESERVED3 = 4126,
    S_RESERVED4 = 4127,
    S_LMANDATA_ST = 4128,
    S_GMANDATA_ST = 4129,
    S_MANFRAMEREL_ST = 4130,
    S_MANREGISTER_ST = 4131,
    S_MANSLOT_ST = 4132,
    S_MANMANYREG_ST = 4133,
    S_MANREGREL_ST = 4134,
    S_MANMANYREG2_ST = 4135,
    S_MANTYPREF = 4136,
    S_UNAMESPACE_ST = 4137,
    S_ST_MAX = 4352,
    S_WITH32 = 4356,
    S_MANYREG = 4362,
    S_LPROCMIPS = 4372,
    S_GPROCMIPS = 4373,
    S_MANYREG2 = 4375,
    S_LPROCIA64 = 4376,
    S_GPROCIA64 = 4377,
    S_LOCALSLOT = 4378,
    S_PARAMSLOT = 4379,
    S_MANFRAMEREL = 4382,
    S_MANREGISTER = 4383,
    S_MANSLOT = 4384,
    S_MANMANYREG = 4385,
    S_MANREGREL = 4386,
    S_MANMANYREG2 = 4387,
    S_UNAMESPACE = 4388,
    S_DATAREF = 4390,
    S_ANNOTATIONREF = 4392,
    S_TOKENREF = 4393,
    S_GMANPROC = 4394,
    S_LMANPROC = 4395,
    S_ATTR_FRAMEREL = 4398,
    S_ATTR_REGISTER = 4399,
    S_ATTR_REGREL = 4400,
    S_ATTR_MANYREG = 4401,
    S_SEPCODE = 4402,
    S_LOCAL_2005 = 4403,
    S_DEFRANGE_2005 = 4404,
    S_DEFRANGE2_2005 = 4405,
    S_DISCARDED = 4411,
    S_LPROCMIPS_ID = 4424,
    S_GPROCMIPS_ID = 4425,
    S_LPROCIA64_ID = 4426,
    S_GPROCIA64_ID = 4427,
    S_DEFRANGE_HLSL = 4432,
    S_GDATA_HLSL = 4433,
    S_LDATA_HLSL = 4434,
    S_LOCAL_DPC_GROUPSHARED = 4436,
    S_DEFRANGE_DPC_PTR_TAG = 4439,
    S_DPC_SYM_TAG_MAP = 4440,
    S_ARMSWITCHTABLE = 4441,
    S_POGODATA = 4444,
    S_INLINESITE2 = 4445,
    S_MOD_TYPEREF = 4447,
    S_REF_MINIPDB = 4448,
    S_PDBMAP = 4449,
    S_GDATA_HLSL32 = 4450,
    S_LDATA_HLSL32 = 4451,
    S_GDATA_HLSL32_EX = 4452,
    S_LDATA_HLSL32_EX = 4453,
    S_FASTLINK = 4455,
    S_INLINEES = 4456,
    S_END = 6,
    S_INLINESITE_END = 4430,
    S_PROC_ID_END = 4431,
    S_THUNK32 = 4354,
    S_TRAMPOLINE = 4396,
    S_SECTION = 4406,
    S_COFFGROUP = 4407,
    S_EXPORT = 4408,
    S_LPROC32 = 4367,
    S_GPROC32 = 4368,
    S_LPROC32_ID = 4422,
    S_GPROC32_ID = 4423,
    S_LPROC32_DPC = 4437,
    S_LPROC32_DPC_ID = 4438,
    S_REGISTER = 4358,
    S_PUB32 = 4366,
    S_PROCREF = 4389,
    S_LPROCREF = 4391,
    S_ENVBLOCK = 4413,
    S_INLINESITE = 4429,
    S_LOCAL = 4414,
    S_DEFRANGE = 4415,
    S_DEFRANGE_SUBFIELD = 4416,
    S_DEFRANGE_REGISTER = 4417,
    S_DEFRANGE_FRAMEPOINTER_REL = 4418,
    S_DEFRANGE_SUBFIELD_REGISTER = 4419,
    S_DEFRANGE_FRAMEPOINTER_REL_FULL_SCOPE = 4420,
    S_DEFRANGE_REGISTER_REL = 4421,
    S_BLOCK32 = 4355,
    S_LABEL32 = 4357,
    S_OBJNAME = 4353,
    S_COMPILE2 = 4374,
    S_COMPILE3 = 4412,
    S_FRAMEPROC = 4114,
    S_CALLSITEINFO = 4409,
    S_FILESTATIC = 4435,
    S_HEAPALLOCSITE = 4446,
    S_FRAMECOOKIE = 4410,
    S_CALLEES = 4442,
    S_CALLERS = 4443,
    S_UDT = 4360,
    S_COBOLUDT = 4361,
    S_BUILDINFO = 4428,
    S_BPREL32 = 4363,
    S_REGREL32 = 4369,
    S_CONSTANT = 4359,
    S_MANCONSTANT = 4397,
    S_LDATA32 = 4364,
    S_GDATA32 = 4365,
    S_LMANDATA = 4380,
    S_GMANDATA = 4381,
    S_LTHREAD32 = 4370,
    S_GTHREAD32 = 4371,
};

const SectionContrSubstreamVersion  = enum(u32) {
  Ver60 = 0xeffe0000 + 19970605,
  V2 = 0xeffe0000 + 20140516
};

const RecordPrefix = packed struct {
    RecordLen: u16, /// Record length, starting from &RecordKind.
    RecordKind: u16, /// Record kind enum (SymRecordKind or TypeRecordKind)
};

pub const Pdb = struct {
    in_file: os.File,
    allocator: *mem.Allocator,
    coff: *Coff,

    msf: Msf,

    pub fn openFile(self: *Pdb, coff: *Coff, file_name: []u8) !void {
        self.in_file = try os.File.openRead(file_name);
        self.allocator = coff.allocator;
        self.coff = coff;

        try self.msf.openFile(self.allocator, self.in_file);
    }

    pub fn getStreamById(self: *Pdb, id: u32) ?*MsfStream {
        if (id >= self.msf.streams.len)
            return null;
        return &self.msf.streams[id];
    }

    pub fn getStream(self: *Pdb, stream: StreamType) ?*MsfStream {
        const id = @enumToInt(stream);
        return self.getStreamById(id);
    }

    pub fn getSourceLine(self: *Pdb, address: usize) !void {
        const dbi = self.getStream(StreamType.Dbi) orelse return error.InvalidDebugInfo;

        // Dbi Header
        var header: DbiStreamHeader = undefined;
        try dbi.stream.readStruct(DbiStreamHeader, &header);
        std.debug.warn("{}\n", header);
        warn("after header dbi stream at {} (file offset)\n", dbi.getFilePos());

        var modules = ArrayList(Module).init(self.allocator);

        // Module Info Substream
        var mod_info_offset: usize = 0;
        while (mod_info_offset != header.ModInfoSize) {
            var mod_info: ModInfo = undefined;
            try dbi.stream.readStruct(ModInfo, &mod_info);
            std.debug.warn("{}\n", mod_info);
            var this_record_len: usize = @sizeOf(ModInfo);

            const module_name = try dbi.readNullTermString(self.allocator);
            std.debug.warn("module_name '{}'\n", module_name);
            this_record_len += module_name.len + 1;

            const obj_file_name = try dbi.readNullTermString(self.allocator);
            std.debug.warn("obj_file_name '{}'\n", obj_file_name);
            this_record_len += obj_file_name.len + 1;

            const march_forward_bytes = this_record_len % 4;
            if (march_forward_bytes != 0) {
                try dbi.seekForward(march_forward_bytes);
                this_record_len += march_forward_bytes;
            }

            try modules.append(Module{
                .mod_info = mod_info,
                .module_name = module_name,
                .obj_file_name = obj_file_name,
            });

            mod_info_offset += this_record_len;
            if (mod_info_offset > header.ModInfoSize)
                return error.InvalidDebugInfo;
        }

        // Section Contribution Substream
        var sect_contribs = ArrayList(SectionContribEntry).init(self.allocator);
        std.debug.warn("looking at Section Contributinos now\n");
        var sect_cont_offset: usize = 0;
        if (header.SectionContributionSize != 0) {
            const ver = @intToEnum(SectionContrSubstreamVersion, try dbi.stream.readIntLe(u32));
            if (ver != SectionContrSubstreamVersion.Ver60)
                return error.InvalidDebugInfo;
            sect_cont_offset += @sizeOf(u32);
        }
        while (sect_cont_offset != header.SectionContributionSize) {
            const entry = try sect_contribs.addOne();
            try dbi.stream.readStruct(SectionContribEntry, entry);
            std.debug.warn("{}\n", entry);
            sect_cont_offset += @sizeOf(SectionContribEntry);

            if (sect_cont_offset > header.SectionContributionSize)
                return error.InvalidDebugInfo;
        }
        //std.debug.warn("looking at section map now\n");
        //if (header.SectionMapSize == 0)
        //    return error.MissingDebugInfo;

        //var sect_map_hdr: SectionMapHeader = undefined;
        //try dbi.stream.readStruct(SectionMapHeader, &sect_map_hdr);

        //const sect_entries = try self.allocator.alloc(SectionMapEntry, sect_map_hdr.Count);
        //const as_bytes = @sliceToBytes(sect_entries);
        //if (as_bytes.len + @sizeOf(SectionMapHeader) != header.SectionMapSize)
        //    return error.InvalidDebugInfo;
        //try dbi.stream.readNoEof(as_bytes);

        //for (sect_entries) |sect_entry| {
        //    std.debug.warn("{}\n", sect_entry);
        //}

        const mod_index = for (sect_contribs.toSlice()) |sect_contrib| {
            const coff_section = self.coff.sections.toSlice()[sect_contrib.Section];
            std.debug.warn("looking in coff name: {}\n", mem.toSliceConst(u8, &coff_section.header.name));

            const vaddr_start = coff_section.header.virtual_address + sect_contrib.Offset;
            const vaddr_end = vaddr_start + sect_contrib.Size;
            if (address >= vaddr_start and address < vaddr_end) {
                std.debug.warn("found sect contrib: {}\n", sect_contrib);
                break sect_contrib.ModuleIndex;
            }
        } else return error.MissingDebugInfo;

        const mod = &modules.toSlice()[mod_index];
        const modi = self.getStreamById(mod.mod_info.ModuleSymStream) orelse return error.InvalidDebugInfo;

        const signature = try modi.stream.readIntLe(u32);
        if (signature != 4)
            return error.InvalidDebugInfo;

        const symbols = try self.allocator.alloc(u8, mod.mod_info.SymByteSize - 4);
        std.debug.warn("read {} bytes of symbol info\n", symbols.len);
        try modi.stream.readNoEof(symbols);

        if (mod.mod_info.C11ByteSize != 0)
            return error.InvalidDebugInfo;

        if (mod.mod_info.C13ByteSize != 0) {
            std.debug.warn("read C13 line info\n");
        }

        // TODO: locate corresponding source line information
    }
};

// see https://llvm.org/docs/PDB/MsfFile.html
const Msf = struct {
    directory: MsfStream,
    streams: []MsfStream,

    fn openFile(self: *Msf, allocator: *mem.Allocator, file: os.File) !void {
        var file_stream = io.FileInStream.init(file);
        const in = &file_stream.stream;

        var superblock: SuperBlock = undefined;
        try in.readStruct(SuperBlock, &superblock);

        if (!mem.eql(u8, superblock.FileMagic, SuperBlock.file_magic))
            return error.InvalidDebugInfo;

        switch (superblock.BlockSize) {
            // llvm only supports 4096 but we can handle any of these values
            512, 1024, 2048, 4096 => {},
            else => return error.InvalidDebugInfo
        }

        if (superblock.NumBlocks * superblock.BlockSize != try file.getEndPos())
            return error.InvalidDebugInfo;

        self.directory = try MsfStream.init(
            superblock.BlockSize,
            blockCountFromSize(superblock.NumDirectoryBytes, superblock.BlockSize),
            superblock.BlockSize * superblock.BlockMapAddr,
            file,
            allocator,
        );

        const stream_count = try self.directory.stream.readIntLe(u32);
        warn("stream count {}\n", stream_count);

        const stream_sizes = try allocator.alloc(u32, stream_count);
        for (stream_sizes) |*s| {
            const size = try self.directory.stream.readIntLe(u32);
            s.* = blockCountFromSize(size, superblock.BlockSize);
            warn("stream {}B {} blocks\n", size, s.*);
        }

        self.streams = try allocator.alloc(MsfStream, stream_count);
        for (self.streams) |*stream, i| {
            stream.* = try MsfStream.init(
                superblock.BlockSize,
                stream_sizes[i],
                // MsfStream.init expects the file to be at the part where it reads [N]u32
                try file.getPos(),
                file,
                allocator,
            );
        }
    }
};

fn blockCountFromSize(size: u32, block_size: u32) u32 {
    return (size + block_size - 1) / block_size;
}

// https://llvm.org/docs/PDB/MsfFile.html#the-superblock
const SuperBlock = packed struct {
    /// The LLVM docs list a space between C / C++ but empirically this is not the case.
    const file_magic = "Microsoft C/C++ MSF 7.00\r\n\x1a\x44\x53\x00\x00\x00";

    FileMagic: [file_magic.len]u8,

    /// The block size of the internal file system. Valid values are 512, 1024,
    /// 2048, and 4096 bytes. Certain aspects of the MSF file layout vary depending
    /// on the block sizes. For the purposes of LLVM, we handle only block sizes of
    /// 4KiB, and all further discussion assumes a block size of 4KiB.
    BlockSize: u32,

    /// The index of a block within the file, at which begins a bitfield representing
    /// the set of all blocks within the file which are “free” (i.e. the data within
    /// that block is not used). See The Free Block Map for more information. Important:
    /// FreeBlockMapBlock can only be 1 or 2!
    FreeBlockMapBlock: u32,

    /// The total number of blocks in the file. NumBlocks * BlockSize should equal the
    /// size of the file on disk.
    NumBlocks: u32,

    /// The size of the stream directory, in bytes. The stream directory contains
    /// information about each stream’s size and the set of blocks that it occupies.
    /// It will be described in more detail later.
    NumDirectoryBytes: u32,

    Unknown: u32,

    /// The index of a block within the MSF file. At this block is an array of
    /// ulittle32_t’s listing the blocks that the stream directory resides on.
    /// For large MSF files, the stream directory (which describes the block
    /// layout of each stream) may not fit entirely on a single block. As a
    /// result, this extra layer of indirection is introduced, whereby this
    /// block contains the list of blocks that the stream directory occupies,
    /// and the stream directory itself can be stitched together accordingly.
    /// The number of ulittle32_t’s in this array is given by
    /// ceil(NumDirectoryBytes / BlockSize).
    BlockMapAddr: u32,

};

const MsfStream = struct {
    in_file: os.File,
    pos: usize,
    blocks: []u32,
    block_size: u32,

    /// Implementation of InStream trait for Pdb.MsfStream
    stream: Stream,

    pub const Error = @typeOf(read).ReturnType.ErrorSet;
    pub const Stream = io.InStream(Error);

    fn init(block_size: u32, block_count: u32, pos: usize, file: os.File, allocator: *mem.Allocator) !MsfStream {
        var stream = MsfStream {
            .in_file = file,
            .pos = 0,
            .blocks = try allocator.alloc(u32, block_count),
            .block_size = block_size,
            .stream = Stream {
                .readFn = readFn,
            },
        };

        var file_stream = io.FileInStream.init(file);
        const in = &file_stream.stream;
        try file.seekTo(pos);

        warn("stream with blocks");
        var i: u32 = 0;
        while (i < block_count) : (i += 1) {
            stream.blocks[i] = try in.readIntLe(u32);
            warn(" {}", stream.blocks[i]);
        }
        warn("\n");

        return stream;
    }

    fn readNullTermString(self: *MsfStream, allocator: *mem.Allocator) ![]u8 {
        var list = ArrayList(u8).init(allocator);
        defer list.deinit();
        while (true) {
            const byte = try self.stream.readByte();
            if (byte == 0) {
                return list.toSlice();
            }
            try list.append(byte);
        }
    }

    fn read(self: *MsfStream, buffer: []u8) !usize {
        var block_id = self.pos / self.block_size;
        var block = self.blocks[block_id];
        var offset = self.pos % self.block_size;

        //std.debug.warn("seek {} read {}B: block_id={} block={} offset={}\n",
        //    block * self.block_size + offset,
        //    buffer.len, block_id, block, offset);

        try self.in_file.seekTo(block * self.block_size + offset);
        var file_stream = io.FileInStream.init(self.in_file);
        const in = &file_stream.stream;

        var size: usize = 0;
        for (buffer) |*byte| {
            byte.* = try in.readByte();           

            offset += 1;
            size += 1;

            // If we're at the end of a block, go to the next one.
            if (offset == self.block_size) {
                offset = 0;
                block_id += 1;
                block = self.blocks[block_id];
                try self.in_file.seekTo(block * self.block_size);
            }
        }

        self.pos += size;
        return size;
    }

    fn seekForward(self: *MsfStream, len: usize) !void {
        self.pos += len;
        if (self.pos >= self.blocks.len * self.block_size)
            return error.EOF;
    }

    fn seekTo(self: *MsfStream, len: usize) !void {
        self.pos = len;
        if (self.pos >= self.blocks.len * self.block_size)
            return error.EOF;
    }

    fn getSize(self: *const MsfStream) usize {
        return self.blocks.len * self.block_size;
    }

    fn getFilePos(self: MsfStream) usize {
        const block_id = self.pos / self.block_size;
        const block = self.blocks[block_id];
        const offset = self.pos % self.block_size;

        return block * self.block_size + offset;
    }

    fn readFn(in_stream: *Stream, buffer: []u8) Error!usize {
        const self = @fieldParentPtr(MsfStream, "stream", in_stream);
        return self.read(buffer);
    }
};
