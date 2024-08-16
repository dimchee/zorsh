const rl = @import("raylib");
const std = @import("std");

const radius = 0.5;
const FireRate = 3.0; // in bullets per second
const BulletSpeed = 0.2; // in units per frame
const PlayerSpeed = 0.1; // in units per frame
const height = 2; // player and enemy height
const dmg = 5;
const map =
    \\| |_| |_|
    \\| |  _  |
    \\| |_ _| |
    \\|_______|
;
// const map =
//     \\ _ _ _
//     \\|_|_|_|
//     \\|_|_|_|
//     \\|_|_|_|
// ;

const Controler = struct {
    shoot: bool,
    direction: rl.Vector2,
    delta: rl.Vector2,

    fn getInput() Controler {
        var vec = rl.Vector2.init(0, 0);
        var shoot = false;
        if (rl.isKeyDown(rl.KeyboardKey.key_w)) {
            vec.y += 1;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
            vec.y -= 1;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_a)) {
            vec.x += 1;
        }
        if (rl.isKeyDown(rl.KeyboardKey.key_d)) {
            vec.x -= 1;
        }
        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) or rl.isKeyDown(rl.KeyboardKey.key_space)) {
            shoot = true;
        }
        vec = vec.normalize().scale(PlayerSpeed);
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
    fn init(allocator: std.mem.Allocator) Evil {
        return .{
            .enemies = std.ArrayList(Enemy).init(allocator),
            .rng = std.rand.DefaultPrng.init(0),
        };
    }
    fn draw(self: *const Evil) void {
        for (self.enemies.items) |e| {
            e.draw();
        }
    }
    fn update(self: *Evil, target: *const Player) void {
        for (self.enemies.items) |*e| {
            e.update(target);
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
    fn draw(self: *const Enemy) void {
        const start = rl.Vector3.init(self.position.x, radius, self.position.y);
        const end = rl.Vector3.init(self.position.x, height - radius, self.position.y);
        rl.drawCapsule(start, end, radius, 10, 1, rl.Color.fromNormalized(rl.Vector4.init(
            @as(f32, @floatFromInt(self.health)) / 100.0,
            0,
            0.2,
            1,
        )));
    }
    fn update(self: *Enemy, target: *const Player) void {
        const displacement = target.position.subtract(self.position).normalize().scale(0.05);
        self.position = rl.Vector2.add(self.position, displacement);
    }
};

const Dir = enum { Vertical, Horizontal };

const Wall = struct {
    position: rl.Vector2,
    size: rl.Vector3,
    fn init(pos: rl.Vector2, dir: Dir) Wall {
        const size = switch (dir) {
            Dir.Horizontal => rl.Vector3.init(3, 2, 0.2),
            Dir.Vertical => rl.Vector3.init(0.2, 2, 3),
        };
        return .{ .position = pos, .size = size };
    }
    fn draw(self: *const Wall) void {
        const pos = rl.Vector3.init(self.position.x, 1, self.position.y);
        rl.drawCubeV(pos, self.size, rl.Color.dark_blue);
    }
};
const Dungeon = struct {
    walls: std.ArrayList(Wall),
    rng: std.rand.DefaultPrng,
    fn init(allocator: std.mem.Allocator) !Dungeon {
        var walls = std.ArrayList(Wall).init(allocator);
        var x: f32 = 0;
        var y: f32 = 0;
        for (map) |c| {
            switch (c) {
                '\n' => {
                    x = 0;
                    y += 1;
                },
                '|' => {
                    const pos = rl.Vector2.init(1.5 * x + 0.5, 3 * y + 0.5);
                    try walls.append(Wall.init(pos, Dir.Vertical));
                    x += 1;
                },
                '_' => {
                    const pos = rl.Vector2.init(1.5 * x + 0.5, 3 * y + 0.5 + 1.5);
                    try walls.append(Wall.init(pos, Dir.Horizontal));
                    x += 1;
                },
                else => {
                    x += 1;
                },
            }
        }
        return .{
            .walls = walls,
            .rng = std.rand.DefaultPrng.init(0),
        };
    }
    fn draw(self: *const Dungeon) void {
        for (self.walls.items) |w| {
            w.draw();
        }
    }
};

const World = struct {
    player: Player,
    gun: Gun,
    evil: Evil,
    dungeon: Dungeon,
    fn init(arena: *std.heap.ArenaAllocator) !World {
        var world = .{
            .player = Player.init(),
            .gun = Gun.init(arena.allocator()),
            .evil = Evil.init(arena.allocator()),
            .dungeon = try Dungeon.init(arena.allocator()),
        };
        try world.evil.addRandomEnemy();
        try world.evil.addRandomEnemy();
        return world;
    }
    fn update(self: *World, movement: Controler) !void {
        self.player.update(movement);
        try doShooting(&movement, &self.gun, &self.player);
        self.gun.update();
        self.evil.update(&self.player);
        checkCollisions(&self.gun, &self.evil);
    }
    fn draw(self: *const World) void {
        self.player.camera.begin();
        defer self.player.camera.end();

        for (0..100) |i| {
            for (0..100) |j| {
                const x: f32 = @floatFromInt(i);
                const z: f32 = @floatFromInt(j);
                rl.drawPlane(rl.Vector3.init(x - 50, 0, z - 50), rl.Vector2.init(1, 1), if ((i + j) % 2 == 0) rl.Color.white else rl.Color.blue);
            }
        }
        self.player.draw();
        self.gun.draw();
        self.evil.draw();
        self.dungeon.draw();
    }
};

pub fn main() anyerror!void {
    rl.initWindow(1600, 900, "Zorsh");
    defer rl.closeWindow();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var world = try World.init(&arena);

    // rl.disableCursor();
    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        try world.update(Controler.getInput());

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.ray_white);
        world.draw();
    }
}
