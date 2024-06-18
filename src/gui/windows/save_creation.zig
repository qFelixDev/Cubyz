const std = @import("std");

const main = @import("root");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

pub fn openWorld(name: []const u8) void {
	std.log.info("Opening world {s}", .{name});
	main.server.thread = std.Thread.spawn(.{}, main.server.start, .{name}) catch |err| {
		std.log.err("Encountered error while starting server thread: {s}", .{@errorName(err)});
		return;
	};

	const connection = ConnectionManager.init(main.settings.defaultPort+1, false) catch |err| {
		std.log.err("Encountered error while opening connection: {s}", .{@errorName(err)});
		return;
	};
	connection.world = &main.game.testWorld;
	main.game.testWorld.init("127.0.0.1", connection) catch |err| {
		std.log.err("Encountered error while opening world: {s}", .{@errorName(err)});
	};
	main.game.world = &main.game.testWorld;
	for(gui.openWindows.items) |openWindow| {
		gui.closeWindow(openWindow);
	}
	gui.openHud();
}

var textInput: *TextInput = undefined;

fn createWorld(_: usize) void {
	flawedCreateWorld() catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
	};
}

fn flawedCreateWorld() !void {
	const worldName = textInput.currentString.items;
	const saveFolder = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{worldName}) catch unreachable;
	defer main.stackAllocator.free(saveFolder);
	if(std.fs.cwd().openDir(saveFolder, .{})) |_dir| {
		var dir = _dir;
		dir.close();
		return error.AlreadyExists;
	} else |_| {}
	try main.files.makeDir(saveFolder);
	{
		const generatorSettingsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/generatorSettings.json", .{worldName}) catch unreachable;
		defer main.stackAllocator.free(generatorSettingsPath);
		const generatorSettings = main.JsonElement.initObject(main.stackAllocator);
		defer generatorSettings.free(main.stackAllocator);
		const climateGenerator = main.JsonElement.initObject(main.stackAllocator);
		climateGenerator.put("id", "cubyz:noise_based_voronoi"); // TODO: Make this configurable
		generatorSettings.put("climateGenerator", climateGenerator);
		const mapGenerator = main.JsonElement.initObject(main.stackAllocator);
		mapGenerator.put("id", "cubyz:mapgen_v1"); // TODO: Make this configurable
		generatorSettings.put("mapGenerator", mapGenerator);
		try main.files.writeJson(generatorSettingsPath, generatorSettings);
	}
	{ // Make assets subfolder
		const assetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets", .{worldName}) catch unreachable;
		defer main.stackAllocator.free(assetsPath);
		try main.files.makeDir(assetsPath);
	}
	// TODO: Make the seed configurable
	gui.windowlist.save_selection.openWorld(worldName);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	var num: usize = 1;
	var buf: [32]u8 = undefined;
	while (true) {
		var dir = std.fs.cwd().openDir(std.fmt.bufPrint(&buf, "saves/Save{}", .{num}) catch unreachable, .{}) catch break;
		dir.close();
		num += 1;
	}
	const name = std.fmt.bufPrint(&buf, "Save{}", .{num}) catch unreachable;
	textInput = TextInput.init(.{0, 0}, 128, 22, name, .{.callback = &createWorld});
	list.add(textInput);
	list.add(Button.initText(.{0, 0}, 128, "Create World", .{.callback = &createWorld}));

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}