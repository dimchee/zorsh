const rl = @import("raylib");
const std = @import("std");

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

const radius = 0.5;
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
    deathTime: f64,
    fn isDead(self: *const Bullet) bool {
        return self.deathTime < rl.getTime();
    }
    fn compare(_: void, a: Bullet, b: Bullet) std.math.Order {
        return std.math.order(a.deathTime, b.deathTime);
    }
};
const Alive: Bullet = Bullet{ .pos = undefined, .dir = undefined, .deathTime = 0 };

const FireRate = 3.0; // in bullets per second
const BulletSpeed = 0.2; // in units per frame
const Gun = struct {
    bullets: std.PriorityQueue(Bullet, void, Bullet.compare),
    lastFired: f64,
    fn isReadyToFire(self: Gun) bool {
        return self.lastFired + 1.0 / FireRate < rl.getTime();
    }
    fn init(allocator: std.mem.Allocator) Gun {
        return .{
            .bullets = std.PriorityQueue(Bullet, void, Bullet.compare).init(allocator, {}),
            .lastFired = rl.getTime(),
        };
    }
    fn fire(self: *Gun, bullet: Bullet) !void {
        if (self.isReadyToFire()) {
            try self.bullets.add(bullet);
            self.lastFired = rl.getTime();
        }
    }
    fn closestBullet(self: *const Gun, point: rl.Vec2) usize {
        var minSqrDist = std.math.floatMax(f32);
        var minInd = 0;
        for (self.bullets.items, 0..) |bullet, i| {
            const dSqr = bullet.pos.subtract(point).lengthSqr();
            if (dSqr < minSqrDist) {
                minSqrDist = dSqr;
                minInd = i;
            }
        }
        return minInd;
    }
    fn draw(self: *const Gun) void {
        for (self.bullets.items) |bullet| {
            const pos = rl.Vector3.init(bullet.pos.x, 1.2, bullet.pos.y);
            rl.drawSphere(pos, 0.1, rl.Color.white);
        }
    }
    fn update(self: *Gun) void {
        if (self.bullets.peek()) |x| {
            if (x.isDead()) {
                _ = self.bullets.remove();
            }
        }
        for (self.bullets.items) |*b| {
            b.pos = b.pos.add(b.dir.normalize().scale(BulletSpeed));
        }
    }
};

const dmg = 5;
fn checkCollisions(gun: *Gun, evil: *Evil) void {
    for (gun.bullets.items, 0..) |bullet, bulletI| {
        for (evil.enemies.items, 0..) |*enemy, enemyI| {
            if (rl.checkCollisionCircles(bullet.pos, 0.1, enemy.position, radius)) {
                if (enemy.health < dmg) {
                    _ = evil.enemies.swapRemove(enemyI);
                } else enemy.health -= dmg;
                _ = gun.bullets.removeIndex(bulletI);
                return;
            }
        }
    }
}

fn doShooting(controler: *const Controler, bullets: *Gun, player: *const Player) !void {
    if (controler.shoot) {
        try bullets.fire(Bullet{
            .pos = player.position,
            .dir = controler.direction,
            .deathTime = rl.getTime() + 2,
        });
    }
}

const Evil = struct {
    enemies: std.ArrayList(Enemy),
    rng: std.rand.DefaultPrng,
    target: *const Player,
    fn init(allocator: std.mem.Allocator, target: *const Player) Evil {
        return .{
            .enemies = std.ArrayList(Enemy).init(allocator),
            .rng = std.rand.DefaultPrng.init(0),
            .target = target,
        };
    }
    fn draw(self: *const Evil) void {
        for (self.enemies.items) |e| {
            e.draw();
        }
    }
    fn update(self: *Evil) void {
        for (self.enemies.items) |*e| {
            e.update();
        }
        for (self.enemies.items) |*x| {
            for (self.enemies.items) |*y| {
                if (rl.checkCollisionCircles(x.position, radius, y.position, radius)) {
                    const collisionRad = y.position.distance(x.position) - 2 * radius;
                    const dir = y.position.subtract(x.position).scale(collisionRad / 2);
                    x.position = x.position.add(dir);
                    y.position = y.position.subtract(dir);
                }
            }
        }
    }
    fn addRandomEnemy(self: *Evil) !void {
        try self.enemies.append(Enemy{
            .target = self.target,
            .health = 100,
            .position = rl.Vector2.init(
                @floatFromInt(self.rng.random().intRangeAtMost(i32, 2, 5)),
                @floatFromInt(self.rng.random().intRangeAtMost(i32, 2, 5)),
            ),
        });
    }
};
const Enemy = struct {
    position: rl.Vector2,
    health: i32,
    target: *const Player,
    fn draw(self: *const Enemy) void {
        const height = 2;
        const start = rl.Vector3.init(self.position.x, radius, self.position.y);
        const end = rl.Vector3.init(self.position.x, height - radius, self.position.y);
        rl.drawCapsule(start, end, radius, 10, 1, rl.Color.fromNormalized(rl.Vector4.init(
            @as(f32, @floatFromInt(self.health)) / 100.0,
            0,
            0,
            1,
        )));
    }
    fn update(self: *Enemy) void {
        const displacement = self.target.position.subtract(self.position).normalize().scale(0.05);
        self.position = rl.Vector2.add(self.position, displacement);
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var player = Player.init();
    var gun = Gun.init(arena.allocator());

    rl.initWindow(1600, 900, "Zorsh");
    var evil = Evil.init(arena.allocator(), &player);
    try evil.addRandomEnemy();
    try evil.addRandomEnemy();
    defer rl.closeWindow();

    // rl.disableCursor();
    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const movement = Controler.getInput();
        player.update(movement);
        try doShooting(&movement, &gun, &player);
        gun.update();
        evil.update();
        checkCollisions(&gun, &evil);
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
                    rl.drawPlane(rl.Vector3.init(x - 50, 0, z - 50), rl.Vector2.init(1, 1), if ((i + j) % 2 == 0) rl.Color.white else rl.Color.blue);
                }
            }
            player.draw();
            gun.draw();
            evil.draw();
        }
    }
}
