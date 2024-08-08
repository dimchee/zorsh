const rl = @import("raylib");
const std = @import("std");

const MAX_COLUMNS = 32;

const Player = struct {
    position: rl.Vector2,
    camera: rl.Camera3D,
    fn init() Player {
        return Player{
            .position = rl.Vector2.init(0, 0),
            .camera = rl.Camera3D{
                .position = rl.Vector3.init(4, 10, 0),
                .target = rl.Vector3.init(0, 0, 0),
                .up = rl.Vector3.init(0, 1, 0),
                .fovy = 60,
                .projection = rl.CameraProjection.camera_perspective,
            },
        };
    }
    fn draw(self: *const Player) void {
        const radius = 0.5;
        const height = 2;
        const start = rl.Vector3.init(self.position.x, radius, self.position.y);
        const end = rl.Vector3.init(self.position.x, height - radius, self.position.y);
        rl.drawCapsule(start, end, radius, 10, 1, rl.Color.light_gray);
    }
    fn update(self: *Player, movement: rl.Vector2) void {
        self.position = rl.Vector2.add(self.position, movement);
        self.camera.position.x += movement.x;
        self.camera.position.z += movement.y;
        self.camera.target = rl.Vector3.init(self.position.x, 0, self.position.y);
    }
};

const Enemy = struct {
    position: rl.Vector2,
    health: i32,
    target: *const Player,
    fn init(target: *const Player) Enemy {
        var rng = std.rand.DefaultPrng.init(0);
        return Enemy{
            .target = target,
            .health = 100,
            .position = rl.Vector2.init(@floatFromInt(rng.random().intRangeAtMost(i32, -100, 101)), @floatFromInt(rng.random().intRangeAtMost(i32, -100, 101))),
        };
    }
    fn draw(self: *const Enemy) void {
        const radius = 0.5;
        const height = 2;
        const start = rl.Vector3.init(self.position.x, radius, self.position.y);
        const end = rl.Vector3.init(self.position.x, height - radius, self.position.y);
        rl.drawCapsule(start, end, radius, 10, 1, rl.Color.brown);
    }
    fn update(self: *Enemy) void {
        const displacement = rl.Vector2.scale(rl.Vector2.subtract(self.target.*.position, self.position).normalize(), 0.05);
        self.position = rl.Vector2.add(self.position, displacement);
    }
};

pub fn main() anyerror!void {
    var player = Player.init();

    var enemy1 = Enemy.init(&player);

    rl.initWindow(800, 450, "Zorsh");
    defer rl.closeWindow();

    // rl.disableCursor();
    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const movement = getControlerInput();
        player.update(movement);
        // camera.update(rl.CameraMode.camera_third_person);

        enemy1.update();

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.ray_white);
        { // 3D drawing
            player.camera.begin();
            defer player.camera.end();

            for (0..100) |i| {
                for (0..100) |j| {
                    const x: f32 = @floatFromInt(i);
                    const z: f32 = @floatFromInt(j);
                    rl.drawPlane(rl.Vector3.init(x - 50, 0, z - 50), rl.Vector2.init(1, 1), if ((i + j) % 2 == 0) rl.Color.red else rl.Color.blue);
                }
            }
            player.draw();
            enemy1.draw();
        }
    }
}

pub fn getControlerInput() rl.Vector2 {
    var vec = rl.Vector2.init(0, 0);
    if (rl.isKeyDown(rl.KeyboardKey.key_w)) {
        vec.x += 0.1;
    }
    if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
        vec.x -= 0.1;
    }
    if (rl.isKeyDown(rl.KeyboardKey.key_d)) {
        vec.y += 0.1;
    }
    if (rl.isKeyDown(rl.KeyboardKey.key_a)) {
        vec.y -= 0.1;
    }
    var dir = rl.getMousePosition();
    dir.x -= @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
    dir.y -= @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
    return vec.rotate(-std.math.atan2(dir.x, dir.y));
}
