import 'dart:io';
import 'dart:math';

void main() {
  Logger.level = LogLevels.DEBUG;
  var game = new Game();
  Logger.info('main');
  game.start();
}

Map<dynamic, dynamic> cloneMapOfClonables(Map<dynamic, dynamic> from) {
  var newMap = {};
  for (var key in from.keys) {
    newMap[key] = from[key].clone();
  }
  return newMap;
}

class Game {
  Stopwatch watch = new Stopwatch();
  int factoryCount, linkCount;
  GameState gameState;
  StatesHolder statesHolder;
  Distances distances;
  int bombsCount = 2;

  void start() {
    _readInput();
    while (true) {
      watch.reset();
      watch.start();
      _loop();
    }
  }

  void _readInput() {
    factoryCount = int.parse(stdin.readLineSync());
    linkCount = int.parse(stdin.readLineSync());
    Logger.debug(factoryCount);
    Logger.debug(linkCount);
    var raw = [];
    for (var i = 0; i < linkCount; i++) {
      var line = stdin.readLineSync();
      Logger.debug(line);
      raw.add(line.split(' ').map((part) => int.parse(part)).toList());
    }
    distances = new Distances(factoryCount, raw);
  }

  void _readEntities() {
    gameState = new GameState();
    statesHolder = new StatesHolder(gameState);
    int entityCount = int.parse(stdin.readLineSync());
    Logger.debug(entityCount);
    for (int i = 0; i < entityCount; i++) {
      var inputs = stdin.readLineSync().split(' ');
      Logger.debug(inputs.join(' '));
      int entityId = int.parse(inputs[0]);
      String entityType = inputs[1];
      int owner = int.parse(inputs[2]);
      int arg2 = int.parse(inputs[3]);
      int arg3 = int.parse(inputs[4]);
      int arg4 = int.parse(inputs[5]);
      int arg5 = int.parse(inputs[6]);
      switch (entityType) {
        case 'FACTORY':
          gameState.factories[entityId] = new Factory(entityId, owner, arg2, arg3, arg4);
          break;
        case 'TROOP':
          gameState.troops[entityId] = new Troop(entityId, owner, arg2, arg3, arg4, arg5);
          break;
        case 'BOMB':
          gameState.bombs[entityId] = new Bomb(entityId, owner, arg2, arg3, arg4);
      }
    }
  }

  List<int> getTargets(List<int> to) {
    var targets = distances.getDistancesTo(to, statesHolder);
    List<int> ordered = targets.keys.toList();
    ordered.sort((a, b) {
      var aWeight = targets[a]/* + gameState.factories[a].cyborgs*/ - gameState.factories[a].production * 2;
      var bWeight = targets[b]/* + gameState.factories[b].cyborgs*/ - gameState.factories[b].production * 2;
      return aWeight.compareTo(bWeight);
    });

    return ordered;
  }

  void _loop() {
    _readEntities();
    Logger.info('loop');
    var ownFactories = gameState.getOwnFactoriesWithCyborgs().fold([], (List ids, factory) => ids..add(factory.id));
    List<List<int>> bombs = [];
    if (gameState.getScoreDiff() < -10 && bombsCount > 0) {
      Factory target = gameState.getLargestFactories()[0];
      var own = gameState.getOwnFactories().fold([], (List ids, factory) => ids..add(factory.id));
      bombs.add([distances.getClosestSimple(target.id, own), target.id]);
      bombsCount--;
    }
    var closest = getTargets(ownFactories);
    List<List<int>> move = [];
    Map<int, Factory> factoriesGlobal = cloneMapOfClonables(gameState.factories);
    closest.forEach((factoryId) {
      List<List<dynamic>> attackers = [];
      var factoriesLocal = cloneMapOfClonables(factoriesGlobal);
      var closestOurs = distances.getClosest(factoryId, ownFactories, statesHolder);
      var i = 0, cyborgsSent = 0, enemyCyborgs = 0;
      while (i < closestOurs.length && cyborgsSent <= enemyCyborgs) {
        var from = closestOurs[i];
        enemyCyborgs = statesHolder.getFactoryAtStep(factoryId, from[1]).cyborgs;
        var cyborgs = min(enemyCyborgs - cyborgsSent + 1, factoriesLocal[from[0]].cyborgs);
        cyborgsSent += cyborgs;
        factoriesLocal[from[0]].cyborgs -= cyborgs;
        if (cyborgs > 0) {
          attackers.add([from[0], distances.getPath(from[0], factoryId, statesHolder)['path'][1], cyborgs,
            'to ${factoryId}']);
        }
        i++;
      }
      if (cyborgsSent >= enemyCyborgs) {
        move.addAll(attackers);
        factoriesGlobal = factoriesLocal;
      }
    });
    var toPrint = [];
    if (bombs.isNotEmpty)
      toPrint.addAll(bombs.map((single) => 'BOMB '+single.join(' ')));
    if (move.isNotEmpty)
      toPrint.addAll(move.map((single) => 'MOVE '+single.take(3).join(' ')+'; MSG '+single.removeLast()));
    if (toPrint.isNotEmpty)
      print(toPrint.join(';'));
    else
      print('WAIT');
    Logger.info('elapsed: ${watch.elapsedMilliseconds}');
    Logger.debug('end');
  }
}

class StatesHolder {
  List<GameState> states = [];

  StatesHolder(GameState state) {
    states.add(state);
  }

  GameState getStateAtStep(int step) {
    for (var i = 0; i <= step; i++) {
      if (states.length - 1 < i)
        getNextState(states[i-1]);
      if (i == step)
        return states[i];
    }
    throw new Exception('Should return step ${step}');
  }

  GameState getNextState(GameState gameState) {
    int step = states.indexOf(gameState);
    if (states.length > step + 1)
      return states[step + 1];
    var factories = cloneMapOfClonables(gameState.factories);
    var troops = cloneMapOfClonables(gameState.troops);
    var bombs = cloneMapOfClonables(gameState.bombs);

    troops.forEach((id, troop) => troop.turns--);
    bombs.forEach((id, bomb) => bomb.turns--);
    factories.forEach((id, factory) {
      // Increase cyborgs on factory
      if (!factory.isNeutral())
        factory.cyborgs += factory.production;
      // Solve battles
      var myCyborgs = 0, enemyCyborgs = 0;
      List<Troop> participants = troops.values
          .where((Troop troop) => troop.factoryTo == factory.id && troop.turns == 0).toList();
      participants.forEach((troop) {
        if (troop.isMine())
          myCyborgs++;
        else
          enemyCyborgs++;
        troops.remove(troop.id);
      });
      var winner = myCyborgs - enemyCyborgs;
      if (winner != 0) {
        // check if winner and owner are not different players/neutral
        if (winner * factory.owner > 0)
          factory.cyborgs += winner.abs();
        else {
          factory.cyborgs -= winner.abs();
          if (factory.cyborgs < 0) {
            factory.cyborgs = factory.cyborgs.abs();
            factory.owner = winner > 0 ? 1 : -1;
          }
        }
      }
      // Explode bombs
      List<Bomb> toExplode = bombs.values.where((Bomb bomb) => bomb.factoryTo == factory.id && bomb.turns == 0)
          .toList();
      toExplode.forEach((bomb) {
        factory.cyborgs = max(0, factory.cyborgs - max(10, (factory.cyborgs / 2).floor()));
        factory.disabled = 5;
        bombs.remove(bomb.id);
      });
    });

    GameState nextGameState = new GameState();
    nextGameState.factories = factories;
    nextGameState.troops = troops;
    nextGameState.bombs = bombs;
    states.add(nextGameState);

    return nextGameState;
  }

  Factory getFactoryAtStep(int id, int step) {
    var state = getStateAtStep(step);
    return state.factories[id];
  }
}

class GameState {
  Map<int, Factory> factories = {};
  Map<int, Troop> troops = {};
  Map<int, Bomb> bombs = {};

  getOwnCyborgsCount() {
    return factories.values.fold(0, (sum, factory) => sum + (factory.isMine() ? factory.cyborgs : 0));
  }

  List<Factory> getOwnFactoriesWithCyborgs() {
    return factories.values.where((factory) => factory.isMine() && factory.cyborgs > 0).toList();
  }

  List<Factory> getOwnFactories() {
    return factories.values.where((factory) => factory.isMine()).toList();
  }

  Factory getMostCyborgFactory() {
    return getOwnFactoriesWithCyborgs().reduce((a, b) => a.cyborgs > b.cyborgs ? a : b);
  }

  int getCyborgsOnStep(int step, Factory factory) {
    return factory.cyborgs + (!factory.isNeutral() ? factory.production * step : 0);
  }

  List<Troop> getFactoryTroopsComing(Factory factory) {
    return troops.values.where((troop) => troop.factoryTo == factory.id).toList();
  }

  getTargetFactory() {
    return factories.values.fold(0, (sum, factory) => sum + (factory.isMine() ? factory.cyborgs : 0));
  }

  List<Factory> getEnemyFactories() {
    return factories.values.where((factory) => !factory.isMine());
  }

  int getScoreDiff() {
    int my = 0, enemy = 0;
    factories.values.forEach((factory) {
      if (factory.isMine())
        my += factory.cyborgs;
      else if (!factory.isNeutral())
        enemy += factory.cyborgs;
    });
    troops.values.forEach((troop) {
      if (troop.isMine())
        my += troop.cyborgs;
      else
        enemy += troop.cyborgs;
    });
    return my - enemy;
  }

  List<Factory> getLargestFactories() {
    return factories.values.where((factory) => factory.isOpponent()).toList()
      ..sort((a, b) => b.cyborgs.compareTo(a.cyborgs));
  }
}

/**
 * Works with distances preprocessing with Floyd-Warshall algorithm.
 */
class Distances {
  List<List<int>> _matrix;
  List<List<int>> _next;
  Map<StatesHolder, Map<String, Map>> _statePathCache = {};

  Distances(int size, List<List<int>> distances) {
    List<List<int>> init = new List(size);
    _next = new List(size);
    distances.forEach((distance) {
      if (init[distance[0]] == null)
        init[distance[0]] = new List(size);
      if (init[distance[1]] == null)
        init[distance[1]] = new List(size);
      if (_next[distance[0]] == null)
        _next[distance[0]] = new List(size);
      if (_next[distance[1]] == null)
        _next[distance[1]] = new List(size);
      init[distance[0]][distance[1]] = distance[2];
      init[distance[1]][distance[0]] = distance[2];
      _next[distance[0]][distance[1]] = distance[1];
      _next[distance[1]][distance[0]] = distance[0];
    });
    for (var i = 0; i < init.length; i++) {
      init[i][i] = 0;
    }

    _doItFloyd(init);
  }

  _doItFloyd(List<List<int>> init) {
    _matrix = init;
    for (var k = 0; k < _matrix.length; k++) {
      for (var i = 0; i < _matrix.length; i++) {
        for (var j = 0; j < _matrix.length; j++) {
          if (_matrix[i][j] > _matrix[i][k] + _matrix[k][j]) {
            _matrix[i][j] = _matrix[i][k] + _matrix[k][j];
            _next[i][j] = _next[i][k];
          }
        }
      }
    }
  }

  Map getPath(int i, int j, StatesHolder statesHolder) {
    if (i == j)
      throw new Exception('i == j == ${i}');
    if (_statePathCache[statesHolder] == null)
      _statePathCache[statesHolder] = {};
    if (_statePathCache[statesHolder]['${i} ${j}'] != null)
      return _statePathCache[statesHolder]['${i} ${j}'];
    List<int> path = [i];
    int current = i, length = 0, next;
    while (j != current) {
      next = _next[current][j];
      length += _matrix[current][next];
      // Don't try to move via enemy factories with cyborgs
      var factory = statesHolder.getFactoryAtStep(next, length);
      if (!factory.isMine() && factory.cyborgs > 0) {
        length = _matrix[i][j];
        path = [i, j];
        break;
      }
      path.add(next);
      current = next;
    }
    _statePathCache[statesHolder]['${i} ${j}'] = {'length': length, 'path': path};
    return _statePathCache[statesHolder]['${i} ${j}'];
  }

  /**
   * Returns max distance from each [to] to other vertices.
   */
  Map<int, int> getDistancesTo(List<int> to, StatesHolder statesHolder) {
    Map<int, int> distances = {};
    to.forEach((vertex) {
      for (var i = 0; i < _matrix.length; i++) {
          if (to.contains(i))
            continue;
          if (distances[i] == null)
            distances[i] = 0;
          distances[i] = max(distances[i], getPath(vertex, i, statesHolder)['length']);
      }
    });
    return distances;
  }

  List<List<int>> getClosest(int to, List<int> among, StatesHolder statesHolder) {
    Map<int, List<int>> distances = {};
    for (var i = 0; i < _matrix.length; i++) {
      if (to == i || !among.contains(i))
        continue;
      if (distances[i] == null)
        distances[i] = [i, 0];
      distances[i] = [i, max(distances[i][1], getPath(i, to, statesHolder)['length'])];
    }
    List<List<int>> ordered = distances.values.toList()..sort((a, b) => a[1].compareTo(b[1]));

    return ordered;
  }

  int getClosestSimple(int to, List<int> among) {
    int min, closest = 0;
    for (var i = 0; i < _matrix.length; i++) {
      if (to == i || !among.contains(i))
        continue;
      if (min == null || _matrix[i][to] < min) {
        min = _matrix[i][to];
        closest = i;
      }
    }

    return closest;
  }
}

class Factory {
  int id, owner, cyborgs, production, disabled;

  Factory(this.id, this.owner, this.cyborgs, this.production, this.disabled);

  isMine() => owner == 1;

  isNeutral() => owner == 0;

  isOpponent() => owner == -1;

  Factory clone() => new Factory(id, owner, cyborgs, production, disabled);

  String toString() => [id, owner, cyborgs, production, disabled].join(' ');
}

class Troop {
  int id, owner, cyborgs, turns, factoryFrom, factoryTo;

  Troop(this.id, this.owner, this.factoryFrom, this.factoryTo, this.cyborgs, this.turns);

  Troop clone() => new Troop(id, owner, factoryFrom, factoryTo, cyborgs, turns);

  String toString() => [id, owner, cyborgs, turns, factoryFrom, factoryTo].join(' ');

  bool isMine() => owner == 1;
}

class Bomb {
  int id, owner, factoryFrom, factoryTo, turns;

  Bomb(this.id, this.owner, this.factoryFrom, this.factoryTo, this.turns) {
    factoryTo = factoryTo != -1 ? factoryTo : null;
  }

  Bomb clone() => new Bomb(id, owner, factoryFrom, factoryTo, turns);

  String toString() => [id, owner, factoryFrom, factoryTo, turns].join(' ');

  bool isMine() => owner == 1;
}

class Logger {
  static LogLevels level = LogLevels.DISABLE;

  static void debug(message) {
    _log(LogLevels.DEBUG, message);
  }

  static void info(message) {
    _log(LogLevels.INFO, message);
  }

  static void _log(LogLevels _level, message) {
    if (_level.index >= level.index) {
      stderr.writeln(message);
    }
  }
}

enum LogLevels { DEBUG, INFO, DISABLE }