import 'dart:math';
import 'dart:html';
import 'dart:typed_data';

const num CIRCLE = PI * 2;
bool MOBILE = false;

class Controls {
  Map codes;
  Map states;

  Controls() {
    this.codes = {
        37: 'left', 39: 'right', 38: 'forward', 40: 'backward'
    };
    this.states = {
        'left': false, 'right': false, 'forward': false, 'backward': false
    };
    document.addEventListener('keydown', this.keyDown, false);
    document.addEventListener('keyup', this.keyUp, false);
  }

  void keyDown(KeyEvent e) {
    if (this.codes.containsKey(e.keyCode)) {
      var state = this.codes[e.keyCode];
      this.states[state] = true;
    }
  }

  void keyUp(KeyEvent e) {
    if (this.codes.containsKey(e.keyCode)) {
      var state = this.codes[e.keyCode];
      this.states[state] = false;
    }
  }
}

class Bitmap {
  num width;
  num height;
  ImageElement image;

  Bitmap(String src, num width, num height) {
    this.image = new ImageElement();
    this.image.src = src;
    this.width = width;
    this.height = height;
  }
}

class Player {
  num x;
  num y;
  num direction;
  Bitmap weapon;
  num paces;

  Player(num x, num y, num direction) {
    this.x = x;
    this.y = y;
    this.direction = direction;
    this.weapon = new Bitmap('knife_hand.png', 319, 320);
    this.paces = 0;
  }

  void rotate(num angle) {
    this.direction = (this.direction + angle + CIRCLE) % CIRCLE;
  }

  void walk(num distance, GameMap map) {
    var dx = cos(this.direction) * distance;
    var dy = sin(this.direction) * distance;
    if (map.get(this.x + dx, this.y) <= 0) {
      this.x += dx;
    }
    if (map.get(this.x, this.y + dy) <= 0) {
      this.y += dy;
    }
    this.paces += distance;
  }

  void update(Controls controls, GameMap map, num seconds) {
    if (controls.states['left']) {
      this.rotate(-PI * seconds);
    }
    if (controls.states['right']) {
      this.rotate(PI * seconds);
    }
    if (controls.states['forward']) {
      this.walk(3 * seconds, map);
    }
    if (controls.states['backward']) {
      this.walk(-3 * seconds, map);
    }
  }
}

class GameMap {
  num size;
  Uint8List wallGrid;
  Bitmap skybox;
  Bitmap wallTexture;
  num light;

  GameMap(num size) {
    this.size = size;
    this.wallGrid = new Uint8List(size * size);
    this.skybox = new Bitmap('deathvalley_panorama.jpg', 4000, 1290);
    this.wallTexture = new Bitmap('wall_texture.jpg', 1024, 1024);
    this.light = 0;
  }

  num get(num x, num y) {
    x = x.floor();
    y = y.floor();
    if (x < 0 || x > this.size - 1 || y < 0 || y > this.size - 1) {
      return -1;
    }
    return this.wallGrid[y * this.size + x];
  }

  void randomize() {
    var rnd = new Random();
    for (var i = 0; i < this.size * this.size; i++) {
      this.wallGrid[i] = rnd.nextDouble() < 0.3 ? 1 : 0;
    }
  }

  void update(num seconds) {
    var rnd = new Random();
    if (this.light > 0) {
      this.light = max(this.light - 10 * seconds, 0);
    } else if (rnd.nextDouble() * 5 < seconds) {
      this.light = 2;
    }
  }

  List cast(Player point, num angle, num range) {
    var sinv = sin(angle);
    var cosv = cos(angle);
    var noWall = {
        'length2': double.INFINITY
    };


    Map step(num rise, num run, num x, num y, bool inverted) {
      var dict = new Map();
      if (run == 0) {
        return noWall;
      }
      var dx = run > 0 ? (x + 1).floor() - x : (x - 1).ceil() - x;
      var dy = dx * (rise / run);
      return {
          'x': inverted ? y + dy : x + dx, 'y': inverted ? x + dx : y + dy, 'length2': dx * dx + dy * dy
      };
    }

    Map inspect(Map step, num shiftX, num shiftY, num distance, num offset) {
      var dx = cosv < 0 ? shiftX : 0;
      var dy = sinv < 0 ? shiftY : 0;
      step['height'] = get(step['x'] - dx, step['y'] - dy);
      step['distance'] = distance + sqrt(step['length2']);
      if (shiftX != 0) {
        step['shading'] = cosv < 0 ? 2 : 0;
      } else {
        step['shading'] = sinv < 0 ? 2 : 1;
      }
      step['offset'] = offset - offset.floor();
      return step;
    }

    List ray(Map origin) {
      var stepX = step(sinv, cosv, origin['x'], origin['y'], false);
      var stepY = step(cosv, sinv, origin['y'], origin['x'], true);
      var nextStep = stepX['length2'] < stepY['length2'] ? inspect(stepX, 1, 0, origin['distance'], stepX['y']) : inspect(stepY, 0, 1, origin['distance'], stepY['x']);
      if (nextStep['distance'] > range) {
        return [origin];
      }
      var r = [origin];
      r.addAll(ray(nextStep));
      return r;
    }


    return ray({
        'x':point.x, 'y':point.y, 'height':0, 'distance':0
    });
  }
}

class Camera {
  CanvasRenderingContext2D ctx;
  num width;
  num height;
  num resolution;
  num spacing;
  num fov;
  num range;
  num lightRange;
  num scale;

  Camera(CanvasElement canvas, num resolution, num fov) {
    this.ctx = canvas.getContext('2d');
    this.width = canvas.width = (window.innerWidth * 0.5).floor();
    this.height = canvas.height = (window.innerHeight * 0.5).floor();
    this.resolution = resolution;
    this.spacing = this.width / resolution;
    this.fov = fov;
    this.range = MOBILE ? 8 : 14;
    this.lightRange = 5;
    this.scale = (this.width + this.height) / 1200;
  }

  void drawSky(num direction, Bitmap sky, num ambient) {
    var width = this.width * (CIRCLE / this.fov);
    var left = -width * direction / CIRCLE;

    this.ctx.save();
    this.ctx.drawImageScaled(sky.image, left, 0, width, this.height);
    if (left < width - this.width) {
      this.ctx.drawImageScaled(sky.image, left + width, 0, width, this.height);
    }
    if (ambient > 0) {
      this.ctx.fillStyle = '#ffffff';
      this.ctx.globalAlpha = ambient * 0.1;
      this.ctx.fillRect(0, this.height * 0.5, this.width, this.height * 0.5);
    }
    this.ctx.restore();
  }

  void render(Player player, GameMap map) {
    this.drawSky(player.direction, map.skybox, map.light);
    this.drawColumns(player, map);
    this.drawWeapon(player.weapon, player.paces);
  }

  void drawWeapon(Bitmap weapon, num paces) {
    var bobX = cos(paces * 2) * this.scale * 6;
    var bobY = sin(paces * 4) * this.scale * 6;
    var left = this.width * 0.66 + bobX;
    var top = this.height * 0.6 + bobY;
    this.ctx.drawImageScaled(weapon.image, left, top, weapon.width * this.scale, weapon.height * this.scale);
  }

  void drawColumn(num column, List ray, num angle, GameMap map) {
    var ctx = this.ctx;
    var texture = map.wallTexture;
    var left = (column * this.spacing).floor();
    var width = this.spacing.ceil();
    var hit = -1;

    while (++hit < ray.length && ray[hit]['height'] <= 0);

    var rnd = new Random();
    for (var s = ray.length - 1 ; s >= 0; s--) {
      var step = ray[s];
      var rainDrops = pow(rnd.nextDouble(), 3) * s;
      //var rain = (rainDrops > 0) && this.project(0.1, angle, step['distance']);

      if (s == hit) {
        var textureX = (texture.width * step['offset']).floor();
        var wall = this.project(step['height'], angle, step['distance']);

        ctx.globalAlpha = 1;
        ctx.drawImageScaledFromSource(texture.image, textureX, 0, 1, texture.height, left, wall['top'], width, wall['height']);

        ctx.fillStyle = '#000000';
        ctx.globalAlpha = max((step['distance'] + step['shading']) / this.lightRange - map.light, 0);
        ctx.fillRect(left, wall['top'], width, wall['height']);
      }
//      ctx.fillStyle = '#ffffff';
//      ctx.globalAlpha = 0.15;
//      while (--rainDrops > 0){
//        ctx.fillRect(left, rnd.nextDouble() * rain['top'], 1, rain['height']);
//      }
    }
  }

  void drawColumns(Player player, GameMap map) {
    this.ctx.save();
    for (var column = 0; column < this.resolution; column++) {
      var x = column / this.resolution - 0.5;
      var angle = this.fov * (column / this.resolution - 0.5);
      var ray = map.cast(player, player.direction + angle, this.range);
      this.drawColumn(column, ray, angle, map);
    }
    this.ctx.restore();
  }

  Map project(num height, num angle, num distance) {
    var z = distance * cos(angle);
    var wallHeight = this.height * height / z;
    var bottom = this.height / 2 * ( 1 + 1 / z);
    var dict = new Map();
    dict['top'] = bottom - wallHeight;
    dict['height'] = wallHeight;
    return dict;
  }
}

class GameLoop {
  Function callback;
  num lastTime;

  GameLoop() {
    lastTime = 0;
  }

  void start(Function callback) {
    this.callback = callback;
    window.requestAnimationFrame(this.frame);
  }

  void frame(num time) {
    var seconds = (time - this.lastTime) / 1000;
    this.lastTime = time;
    if (seconds < 0.2) {
      this.callback(seconds);
    }
    window.requestAnimationFrame(this.frame);
  }
}

void main() {
  var display = document.getElementById('display');
  var player = new Player(15.3, -1.2, PI * 0.3);
  var map = new GameMap(32);
  var controls = new Controls();
  var camera = new Camera(display, MOBILE ? 160 : 320, PI * 0.4);
  var loop = new GameLoop();
  map.randomize();
  loop.start((num seconds) {
    map.update(seconds);
    player.update(controls, map, seconds);
    camera.render(player, map);
  });
}