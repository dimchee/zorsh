const rl = @import("raylib");
const std = @import("std");

const MAX_COLUMNS = 32;

const Controler = struct {
    shoot: bool,
    direction: rl.Vector2,
    delta: rl.Vector2,

    fn getInput() Controler {
        var vec = rl.Vector2.init(0, 0);
        var shoot = false;
        if (rl.isKeyDown(rl.KeyboardKey.key_w)) {
            vec.y += 0.1;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
            vec.y -= 0.1;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_a)) {
            vec.x += 0.1;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_d)) {
            vec.x -= 0.1;
        }
        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) or rl.isKeyDown(rl.KeyboardKey.key_space)) {
            shoot = true;
        }
        var dir = rl.getMousePosition();
        dir.x -= @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
        dir.y -= @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
        return Controler{
            .shoot = shoot,
            .direction = dir,
            .delta = vec.rotate(-std.math.atan2(dir.x, dir.y)),
        };
    }
};

const Player = struct {
    position: rl.Vector2,
    camera: rl.Camera3D,
    fn init() Player {
        return Player{
            .position = rl.Vector2.init(0, 0),
            .camera = rl.Camera3D{
                .position = rl.Vector3.init(0, 10, 4),
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
    fn update(self: *Player, controler: Controler) void {
        self.position = self.position.add(controler.delta);
        self.camera.position.x += controler.delta.x;
        self.camera.position.z += controler.delta.y;
        self.camera.target = rl.Vector3.init(self.position.x, 0, self.position.y);
    }
};

const Bullet = struct {
    pos: rl.Vector2,
    dir: rl.Vector2,
    spawnTime: f64,
    deathTime: f64,
    fn isDead(self: *const Bullet) bool {
        return self.deathTime < rl.getTime();
    }
    fn compare(_: void, a: Bullet, b: Bullet) std.math.Order {
        return std.math.order(a.deathTime, b.deathTime);
    }
};

const Bullets = struct {
    bullets: std.PriorityDequeue(Bullet, void, Bullet.compare),
    fn init(allocator: std.mem.Allocator) Bullets {
        return .{
            .bullets = std.PriorityDequeue(Bullet, void, Bullet.compare).init(allocator, {}),
        };
    }
    fn fire(self: *Bullets, bullet: Bullet) !void {
        if (self.bullets.peekMax()) |x| {
            if (x.spawnTime + 1 < rl.getTime()) {
                try self.bullets.add(bullet);
            }
        }
        if (self.bullets.count() == 0) {
            try self.bullets.add(bullet);
        }
    }
    fn draw(self: *const Bullets) void {
        for (self.bullets.items) |bullet| {
            const pos = rl.Vector3.init(bullet.pos.x, 2, bullet.pos.y);
            rl.drawSphere(pos, 0.1, rl.Color.white);
        }
    }
    fn update(self: *Bullets) void {
        std.debug.print("All bullets: {any}\n\n", .{self.bullets.items});
        while (self.bullets.count() > 0 and self.bullets.peekMin().?.isDead()) {
            const min = self.bullets.removeMin();
            std.debug.print("minimumBullet = {}", .{min});
        }
        for (self.bullets.items) |*b| {
            b.pos = b.pos.add(b.dir.normalize().scale(0.01));
        }
    }
};

fn doShooting(controler: *const Controler, bullets: *Bullets, player: *const Player) !void {
    std.debug.print("{}", .{rl.getTime()});
    if (controler.shoot) {
        try bullets.fire(Bullet{
            .pos = player.position,
            .dir = controler.direction,
            .spawnTime = rl.getTime(),
            .deathTime = rl.getTime() + 2,
        });
    }
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var player = Player.init();
    var bullets = Bullets.init(arena.allocator());

    rl.initWindow(1600, 900, "Zorsh");
    defer rl.closeWindow();

    // rl.disableCursor();
    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const movement = Controler.getInput();
        player.update(movement);
        try doShooting(&movement, &bullets, &player);
        bullets.update();
        // camera.update(rl.CameraMode.camera_third_person);

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
            bullets.draw();
        }
    }
}
