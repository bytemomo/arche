const std = @import("std");

const out_dir_name = "img";
const cpu_arch: std.Target.Cpu.Arch = .x86_64;

pub fn build(b: *std.Build) void {
    const options = b.addOptions();
    setup(b, options);

    const  optimize = b.standardOptimizeOption(.{ });
    _ = setupKyber(b, options, optimize);
    _= setupLogos(b, options, optimize);

    // use qemu as run method
    const qemu_args = [_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        "/usr/share/edk2/x64/OVMF.4m.fd",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, out_dir_name }),
        "-nographic",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        "-enable-kvm",
        "-cpu",
        "host",
        "-s",
        // This adds to qemu a device that listen on I/O port 0xf4 and
        // when write a byte to that port qemu exits.
        "-device",
        "isa-debug-exit,iobase=0xf4,iosize=0x04",
    };
    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_cmd = b.step("run", "Run QEMU");
    run_qemu_cmd.dependOn(&qemu_cmd.step);
}


fn setup(b: *std.Build, options: *std.Build.Step.Options) void {
    const s_log_level = b.option([]const u8, "log_level", "log_level") orelse "Info";

    const log_level: std.log.Level = b: {
        const eql = std.mem.eql;
        break :b if (eql(u8, s_log_level, "Debug"))
            .debug
        else if (eql(u8, s_log_level, "Info"))
            .info
        else if (eql(u8, s_log_level, "Warn"))
            .warn
        else if (eql(u8, s_log_level, "Error"))
            .err
        else
            @panic("Invalid log level");
    };

    options.addOption(std.log.Level, "log_level", log_level);
}

fn createTypesModule(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("common/types.zig"),
    });
}

fn createArchModule(b: *std.Build, comptime arch: std.Target.Cpu.Arch, types_module: *std.Build.Module) *std.Build.Module {
    const arch_path = switch (arch) {
        .x86_64 => "common/arch/x86_64.zig",
        else => @compileError("Unsupported architecture"),
    };
    const mod = b.createModule(.{
        .root_source_file = b.path(arch_path),
    });
    mod.addImport("types", types_module);
    return mod;
}

fn createBootInfoModule(b: *std.Build, types_module: *std.Build.Module) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("common/boot_info.zig"),
    });
    mod.addImport("types", types_module);
    return mod;
}

fn setupKyber(b: *std.Build, options: *std.Build.Step.Options, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const kyber = b.addExecutable(.{
        .name = "kyber.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kyber/entry.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = cpu_arch,
                .os_tag = .freestanding,
                .ofmt = .elf,
            }),
            .optimize = optimize,
            .code_model = .large,
            .pic = true,
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    kyber.setLinkerScript(b.path("kyber/linker.ld"));
    const kyber_types = createTypesModule(b);
    kyber.root_module.addOptions("option", options);
    kyber.root_module.addImport("types", kyber_types);
    kyber.root_module.addImport("arch", createArchModule(b, cpu_arch, kyber_types));
    kyber.root_module.addImport("boot_info", createBootInfoModule(b, kyber_types));
    b.installArtifact(kyber);

    const install_kyber = b.addInstallFile(
        kyber.getEmittedBin(),
        b.fmt("{s}/{s}", .{out_dir_name, kyber.name}),
    );
    install_kyber.step.dependOn(&kyber.step);
    b.getInstallStep().dependOn(&install_kyber.step);

    return kyber;
}

fn setupLogos(b: *std.Build, options: *std.Build.Step.Options, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {

    const logos = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_module = b.createModule(.{
            .root_source_file = b.path("logos/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = cpu_arch,
                .os_tag =  .uefi,
            }),
            .optimize = optimize,
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    logos.subsystem = .EfiApplication;
    const logos_types = createTypesModule(b);
    logos.root_module.addOptions("option", options);
    logos.root_module.addImport("types", logos_types);
    logos.root_module.addImport("arch", createArchModule(b, cpu_arch, logos_types));
    logos.root_module.addImport("boot_info", createBootInfoModule(b, logos_types));
    b.installArtifact(logos);

    const install_logos = b.addInstallFile(
        logos.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, logos.name })
    );
    install_logos.step.dependOn(&logos.step);
    b.getInstallStep().dependOn(&install_logos.step);

    return logos;
}
