const rl = @import("raylib");
const std = @import("std");

// speeds is in units per frame, rate is in objects per second
pub const config = .{
    .wall = .{ .height = 2, .size = 1 },
    .character = .{ .radius = 0.5, .height = 2, .speed = 0.1 },
    .bullet = .{ .speed = 0.2, .damage = 10, .rate = 10.0, .lifetime = 2 },
    .player = .{ .health = 100, .reward = 1 },
    .enemy = .{ .speedFactor = 0.6, .spawnRate = 0.5, .health = 50, .damage = 2 },
    .map =
    \\ [][][][][][][][][][][][][][][][][][][][]
    \\ []                                    []
    \\ []                 s                  []
    \\ []                                    []
    \\ [][]    [][][][][][][][][]  [][][][][][]
    \\ []           []                       []
    \\ []           []          s            []
    \\ []           []                       []
    \\ [][]    [][][][][][][][]      [][][][][]
    \\ []                []                  []
    \\ []       p        []                  []
    \\ []                []                  []
    \\ [][][][][]    [][][][][][][]    [][][][]
    \\ []                                    []
    \\ []                                    []
    \\ []                                    []
    \\ [][][][][][][][][][][][][][][][][][][][]
    ,
};
// const Rectangle = struct { center: rl.Vector2, size: rl.Vector2 };

const Controller = struct {
    shoot: bool,
    direction: rl.Vector2,
    delta: rl.Vector2,

    fn getInput() Controller {
        var shoot = false;
        const bindings = [_]struct { rl.KeyboardKey, rl.Vector2 }{
            .{ rl.KeyboardKey.key_w, .{ .x = 0, .y = 1 } },
            .{ rl.KeyboardKey.key_s, .{ .x = 0, .y = -1 } },
            .{ rl.KeyboardKey.key_a, .{ .x = 1, .y = 0 } },
            .{ rl.KeyboardKey.key_d, .{ .x = -1, .y = 0 } },
        };
        const vec = for (bindings) |kv| {
            if (rl.isKeyDown(kv[0])) break kv[1];
        } else rl.Vector2{ .x = 0, .y = 0 };

        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) or rl.isKeyDown(rl.KeyboardKey.key_space)) {
            shoot = true;
        }
        var dir = rl.getMousePosition();
        dir.x -= @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
        dir.y -= @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
        return Controller{
            .shoot = shoot,
            .direction = dir,
            .delta = vec.normalize().scale(config.character.speed).rotate(-std.math.atan2(dir.x, dir.y)),
        };
    }
};

const Player = struct {
    health: u32,
    score: u32,
    position: rl.Vector2,
    camera: rl.Camera3D,
    cameraDelta: rl.Vector3,
    fn init(cells: std.AutoHashMap(Position, Cell)) Player {
        const cameraDelta = rl.Vector3.init(0, 10, 4);
        var it = cells.iterator();
        const pos = while (it.next()) |cell| {
            if (cell.value_ptr.* == Cell.Player)
                break cell.key_ptr.toVec2();
        } else rl.Vector2.init(0, 0);
        return .{
            .health = config.player.health,
            .score = 0,
            .position = pos,
            .cameraDelta = cameraDelta,
            .camera = rl.Camera3D{
                .position = cameraDelta,
                .target = rl.Vector3.init(0, 0, 0),
                .up = rl.Vector3.init(0, 1, 0),
                .fovy = 60,
                .projection = rl.CameraProjection.camera_perspective,
            },
        };
    }
    fn draw(self: *const Player) void {
        const start = rl.Vector3.init(self.position.x, config.character.radius, self.position.y);
        const end = rl.Vector3.init(self.position.x, config.character.height - config.character.radius, self.position.y);
        rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.light_gray);
    }
    fn update(self: *Player, controller: Controller) void {
        self.position = self.position.add(controller.delta);
        const pos3d = rl.Vector3.init(self.position.x, 0, self.position.y);
        self.camera.position = pos3d.add(self.cameraDelta);
        self.camera.target = pos3d;
    }
};

const Bullet = struct {
    position: rl.Vector2,
    dir: rl.Vector2,
    deathTime: f64,
    fn isDead(self: *const Bullet) bool {
        return self.deathTime < rl.getTime();
    }
    fn compare(_: void, a: Bullet, b: Bullet) std.math.Order {
        return std.math.order(a.deathTime, b.deathTime);
    }
};

const Gun = struct {
    bullets: std.PriorityQueue(Bullet, void, Bullet.compare),
    lastFired: f64,
    fn isReadyToFire(self: Gun) bool {
        return self.lastFired + 1.0 / config.bullet.rate < rl.getTime();
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
            const dSqr = bullet.position.subtract(point).lengthSqr();
            if (dSqr < minSqrDist) {
                minSqrDist = dSqr;
                minInd = i;
            }
        }
        return minInd;
    }
    fn draw(self: *const Gun) void {
        for (self.bullets.items) |bullet| {
            const pos = rl.Vector3.init(bullet.position.x, 1.2, bullet.position.y);
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
            b.position = b.position.add(b.dir.normalize().scale(config.bullet.speed));
        }
    }
};

fn checkBulletCollision(gun: *Gun, evil: *Evil, player: *Player) void {
    for (gun.bullets.items, 0..) |bullet, bulletI| {
        for (evil.enemies.items, 0..) |*enemy, enemyI| {
            const dir = circlesCollisionDirection(
                .{ .center = bullet.position, .radius = 0.1 },
                .{ .center = enemy.position, .radius = config.character.radius },
            );

            if (dir.lengthSqr() > 0) {
                if (enemy.health < config.bullet.damage) {
                    _ = evil.enemies.swapRemove(enemyI);
                    player.score += config.player.reward;
                } else enemy.health -= config.bullet.damage;
                _ = gun.bullets.removeIndex(bulletI);
                return;
            }
        }
    }
}

fn dynamicCollide(x: anytype, y: anytype) bool {
    const dir = circlesCollisionDirection(
        .{ .center = x.position, .radius = config.character.radius },
        .{ .center = y.position, .radius = config.character.radius },
    );
    if (dir.lengthSqr() > 0) {
        // if (std.mem.eql(u8, @typeName(@TypeOf(y)), "*game.Player")) {
        //     std.debug.print("Collided player health: {}\n", .{y.health});
        // }
        x.position = x.position.add(dir.scale(0.5));
        y.position = y.position.subtract(dir.scale(0.5));
        return true;
    }
    return false;
}

const Circle = struct { center: rl.Vector2, radius: f32 };
fn circlesCollisionDirection(a: Circle, b: Circle) rl.Vector2 {
    const scale = @max(a.radius + b.radius - a.center.distance(b.center), 0);
    return a.center.subtract(b.center).normalize().scale(scale);
}

fn directionToWall(wall: *const Wall, p: rl.Vector2) rl.Vector2 {
    const delta = rl.Vector2.init(wall.size.x / 2, wall.size.z / 2);
    const rect = .{ .min = wall.position.subtract(delta), .max = wall.position.add(delta) };
    return rl.Vector2.init(
        @min(p.x - rect.min.x, 0) + @max(p.x - rect.max.x, 0),
        @min(p.y - rect.min.y, 0) + @max(p.y - rect.max.y, 0),
    );
}

fn staticCollide(wall: *const Wall, x: anytype) void {
    const dir = directionToWall(wall, x.position);
    if (dir.lengthSqr() < config.character.radius * config.character.radius) {
        x.position = dir.normalize().scale(config.character.radius - dir.length()).add(x.position);
    }
}

fn checkCharacterCollision(evil: *Evil, player: *Player, dungeon: *const Dungeon) void {
    for (evil.enemies.items) |*x| {
        for (evil.enemies.items) |*y| {
            _ = dynamicCollide(x, y);
        }
        if (dynamicCollide(x, player)) {
            player.health = if (player.health < config.enemy.damage) 0 else player.health - config.enemy.damage;
        }
    }
    for (dungeon.walls.items) |*static| {
        for (evil.enemies.items) |*x| {
            staticCollide(static, x);
        }
        staticCollide(static, player);
    }
}

fn doShooting(controller: *const Controller, bullets: *Gun, player: *const Player) !void {
    if (controller.shoot) {
        try bullets.fire(Bullet{
            .position = player.position,
            .dir = controller.direction,
            .deathTime = rl.getTime() + config.bullet.lifetime,
        });
    }
}

const Evil = struct {
    enemies: std.ArrayList(Enemy),
    cells: std.AutoHashMap(Position, Cell),
    rng: std.rand.DefaultPrng,
    allocator: std.mem.Allocator,
    fn init(allocator: std.mem.Allocator, cells: std.AutoHashMap(Position, Cell)) Evil {
        return .{
            .allocator = allocator,
            .enemies = std.ArrayList(Enemy).init(allocator),
            .rng = std.rand.DefaultPrng.init(0),
            .cells = cells,
        };
    }
    fn draw(self: *const Evil) void {
        for (self.enemies.items) |e| {
            e.draw();
        }
    }
    fn update(self: *Evil, target: *const Player) !void {
        var hints = std.AutoHashMap(Position, Position).init(self.allocator);
        var q = std.DoublyLinkedList(struct { from: Position, to: Position }){};
        var nodes: [10000]@TypeOf(q).Node = undefined;
        var ind: u32 = 0;
        var pos = Position.fromVec2(target.position);
        nodes[ind] = .{ .data = .{ .from = pos, .to = pos } };
        q.prepend(&nodes[ind]);
        ind += 1;
        while (q.pop()) |hint| {
            pos = hint.data.to;
            if (self.cells.get(pos)) |x|
                if (x == Cell.Wall) continue;
            if (hints.contains(pos)) continue;
            try hints.put(pos, hint.data.from);
            const dxs = [_]i8{ 1, 1, 0, -1, -1, -1, 0, 1 };
            const dys = [_]i8{ 0, 1, 1, 1, 0, -1, -1, -1 };
            for (dxs, dys) |dx, dy| {
                const to = .{ .x = pos.x + dx, .y = pos.y + dy };
                nodes[ind] = .{ .data = .{ .from = pos, .to = to } };
                q.prepend(&nodes[ind]);
                ind += 1;
            }
        }
        for (self.enemies.items) |*e| {
            e.update(hints.get(Position.fromVec2(e.position)).?.toVec2());
        }
    }
    fn add(self: *Evil, enemy: Enemy) !void {
        try self.enemies.append(enemy);
    }
};
const Enemy = struct {
    position: rl.Vector2,
    health: u32,
    fn init(position: rl.Vector2) Enemy {
        return .{ .position = position, .health = config.enemy.health };
    }
    fn draw(self: *const Enemy) void {
        const start = rl.Vector3.init(self.position.x, config.character.radius, self.position.y);
        const end = rl.Vector3.init(self.position.x, config.character.height - config.character.radius, self.position.y);
        rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.fromNormalized(rl.Vector4.init(
            @as(f32, @floatFromInt(self.health)) / @as(f32, config.enemy.health),
            0,
            0.2,
            1,
        )));
    }
    fn update(self: *Enemy, target: rl.Vector2) void {
        self.position = target
            .subtract(self.position)
            .normalize().scale(config.character.speed * config.enemy.speedFactor)
            .add(self.position);
    }
};

const Wall = struct {
    position: rl.Vector2,
    size: rl.Vector3,
    fn init(pos: rl.Vector2) Wall {
        return .{ .position = pos, .size = rl.Vector3.init(config.wall.size, config.wall.height, config.wall.size) };
    }
    fn draw(self: *const Wall) void {
        const pos = rl.Vector3.init(self.position.x, 1, self.position.y);
        rl.drawCubeV(pos, self.size, rl.Color.dark_blue);
    }
};
fn Spawner(what: type) type {
    return struct {
        position: rl.Vector2,
        nextSpawn: f64,
        fn init(position: rl.Vector2) Spawner(what) {
            return .{ .position = position, .nextSpawn = 0.0 };
        }
        fn spawn(self: *Spawner(what)) ?what {
            if (rl.getTime() < self.nextSpawn) return null;
            self.nextSpawn = rl.getTime() + 1.0 / config.enemy.spawnRate;
            return what.init(self.position);
        }
    };
}

const Cell = enum { Wall, Player, Spawner };
const Position = struct {
    x: i32,
    y: i32,
    fn toVec2(self: *const Position) rl.Vector2 {
        return rl.Vector2.init(@floatFromInt(self.x), @floatFromInt(self.y));
    }
    fn fromVec2(vec: rl.Vector2) Position {
        return .{ .x = @intFromFloat(vec.x + 0.5), .y = @intFromFloat(vec.y + 0.5) };
    }
};

fn mapToCells(allocator: std.mem.Allocator) !std.AutoHashMap(Position, Cell) {
    var cells = std.AutoHashMap(Position, Cell).init(allocator);
    var pos = Position{ .x = 0, .y = 0 };
    var last: u8 = '\n';
    for (config.map) |c| {
        const cell: ?Cell = switch (c) {
            ']' => if (last == '[') Cell.Wall else null,
            'p' => if (last != 'p') Cell.Player else null,
            's' => if (last != 's') Cell.Spawner else null,
            else => null,
        };
        if (cell) |t| try cells.put(.{ .x = @divTrunc(pos.x, 2), .y = pos.y }, t);
        last = c;
        pos = if (c == '\n') .{ .x = 0, .y = pos.y + 1 } else .{ .x = pos.x + 1, .y = pos.y };
    }
    return cells;
}

const Dungeon = struct {
    walls: std.ArrayList(Wall),
    spawners: std.ArrayList(Spawner(Enemy)),
    rng: std.rand.DefaultPrng,
    fn init(allocator: std.mem.Allocator, cells: std.AutoHashMap(Position, Cell)) !Dungeon {
        var walls = std.ArrayList(Wall).init(allocator);
        var spawners = std.ArrayList(Spawner(Enemy)).init(allocator);
        var it = cells.iterator();
        while (it.next()) |cell| {
            switch (cell.value_ptr.*) {
                Cell.Wall => try walls.append(Wall.init(cell.key_ptr.toVec2())),
                Cell.Spawner => try spawners.append(Spawner(Enemy).init(cell.key_ptr.toVec2())),
                Cell.Player => {},
            }
        }
        return .{
            .walls = walls,
            .spawners = spawners,
            .rng = std.rand.DefaultPrng.init(0),
        };
    }
    fn draw(self: *const Dungeon) void {
        for (self.walls.items) |w| {
            w.draw();
        }
    }
};

pub const World = struct {
    allocator: std.mem.Allocator,
    player: Player,
    gun: Gun,
    evil: Evil,
    dungeon: Dungeon,
    pub fn init(allocator: std.mem.Allocator) !World {
        const cells = try mapToCells(allocator);
        return .{
            .allocator = allocator,
            .player = Player.init(cells),
            .gun = Gun.init(allocator),
            .evil = Evil.init(allocator, cells),
            .dungeon = try Dungeon.init(allocator, cells),
        };
    }
    pub fn update(self: *World) !void {
        const movement = Controller.getInput();
        for (self.dungeon.spawners.items) |*spawner| {
            if (spawner.spawn()) |enemy| {
                try self.evil.add(enemy);
            }
        }
        self.player.update(movement);
        self.gun.update();
        try self.evil.update(&self.player);
        try doShooting(&movement, &self.gun, &self.player);
        checkBulletCollision(&self.gun, &self.evil, &self.player);
        checkCharacterCollision(&self.evil, &self.player, &self.dungeon);
    }
    pub fn draw(self: *const World) void {
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
