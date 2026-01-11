const std = @import("std");

pub fn build(b: *std.Build) void {

    const s_log_level = b.option(
        []const u8,
        "log_level",
        "log_level",
    ) orelse "info";
    const log_level: std.log.Level = b: {
        const eql = std.mem.eql;
        break :b if (eql(u8, s_log_level, "debug"))
            .debug
        else if (eql(u8, s_log_level, "info"))
            .info
        else if (eql(u8, s_log_level, "warn"))
            .warn
        else if (eql(u8, s_log_level, "error"))
            .err
        else
            @panic("Invalid log level");
    };
    const options = b.addOptions();
    options.addOption(std.log.Level, "log_level", log_level);

    const logos = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_module = b.createModule(.{
            .root_source_file = b.path("logos/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag =  .uefi,
            }),
            .optimize = b.standardOptimizeOption(.{
                // Null
            }),
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    logos.subsystem = .EfiApplication;
    logos.root_module.addOptions("option", options);
    b.installArtifact(logos);


    // This simply change the bootloader's output directory to zig-out/img/
    const out_dir_name = "img";
    const install_logos = b.addInstallFile(
        logos.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, logos.name })
    );
    install_logos.step.dependOn(&logos.step);
    b.getInstallStep().dependOn(&install_logos.step);

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
  };
    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_cmd = b.step("run", "Run QEMU");
    run_qemu_cmd.dependOn(&qemu_cmd.step);
}
