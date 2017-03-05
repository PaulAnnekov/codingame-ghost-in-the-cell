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

List<List> cloneListOfLists(List<List> from) {
  var res = [];
  for (var i = 0; i < from.length; i++) {
    res.add(new List.from(from[i]));
  }
  return res;
}

class Game {
  Stopwatch watch = new Stopwatch();
  int factoryCount, linkCount;
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
    GameState gameState = new GameState();
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
          gameState.troops[entityId] = new Troop(entityId, owner, arg2, arg3, arg4, arg5, false);
          break;
        case 'BOMB':
          gameState.bombs[entityId] = new Bomb(entityId, owner, arg2, arg3, arg4, false);
      }
    }
  }

  List<int> getTargets(List<int> to) {
    GameState gameState = statesHolder.current();
    var targets = gameState.factories.values.where((f) => !f.isMine());
    var ordered = [];
    var own = gameState.factories.values.where((f) => f.isMine());
    var enemies = gameState.factories.values.where((f) => f.isOpponent());
    targets.forEach((target) {
      var minOurs = double.MAX_FINITE.toInt();
      var minEnemy = double.MAX_FINITE.toInt();
      own.forEach((our) {
        minOurs = min(minOurs, distances.getPath(our.id, target.id, statesHolder)['length']);
      });
      enemies.forEach((enemy) {
        if (enemy.id == target.id)
          return;
        minEnemy = min(minEnemy, distances.getPath(enemy.id, target.id, statesHolder, true)['length']);
      });
      if (minOurs < minEnemy && target.production > 0)
        ordered.add([target.id, minOurs]);
    });

    ordered.sort((a, b) {
      var aWeight = a[1] - gameState.factories[a[0]].production * 2 + gameState.factories[a[0]].cyborgs;
      var bWeight = b[1] - gameState.factories[b[0]].production * 2 + gameState.factories[b[0]].cyborgs;
      return aWeight.compareTo(bWeight);
    });
    ordered = ordered.map((f) => f[0]).toList();

    if (ordered.isEmpty) {
      var targetId = distances.getClosest(targets.where((f) => f.isOpponent()).map((f) => f.id).toList(),
          own.map((f) => f.id).toList(), statesHolder);
      if (targetId != null)
        ordered.add(targetId);
    }

    return ordered;
  }

  List<List<int>> strategyBomb() {
    GameState gameState = statesHolder.current();
    List<List<int>> bombs = [];
    if (bombsCount > 0) {
      var targets = gameState.getLargestFactories();
      if (targets.isEmpty)
        return bombs;
      var own = gameState.getOwnFactories().fold([], (List ids, factory) => ids..add(factory.id));
      var from;
      var target = targets.firstWhere((target) {
        if (gameState.bombs.values.any((b) => b.factoryTo == target.id))
          return false;
        from = distances.getClosestSimple(target.id, own);
        var factory = statesHolder.getFactoryAtStep(target.id, from['length']);
        return factory.currentProduction() > 0;
      }, orElse: () => null);
      if (target == null)
        return bombs;
      bombs.add([from['id'], target.id]);
      // TODO: check if length is correct step of explode
      gameState.addBomb(from['id'], target.id, from['length']);
      statesHolder.invalidateFromState(gameState);
      bombsCount--;
    }
    return bombs;
  }

  strategyDefend() {
    GameState gameState = statesHolder.current().clone();
    var ownFactories = gameState.getOwnFactories()..sort((a, b) => b.production.compareTo(a.production));
    var ownWithCyborgs = gameState.getOwnFactoriesWithCyborgs().map((f) => f.id).toList();
    List<String> actions = [];

    ownFactories.forEach((factory) {
      var troops = gameState.getEnemyTroopsTo(factory.id)
        ..sort((a, b) => a.turns.compareTo(b.turns));
      if (troops.isEmpty)
        return;
      var free = 0;
      if (statesHolder.getFactoryAtStep(factory.id, troops.last.turns).isMine()) {
        free = double.MAX_FINITE.toInt();
        for (var i = 0; i <= troops.last.turns; i++) {
          free = min(free, statesHolder.getStep(i).getFreeCyborgs(factory.id));
        }
      }
      // 'free' can be negative if on some step factory was conquered and then taken away again.
      gameState.blockCyborgs(factory.id, free < 0 ? factory.cyborgs : factory.cyborgs - free);
    });
    statesHolder.invalidateFromState(gameState, 0);

    ownFactories.forEach((factory) {
      var troops = gameState.getEnemyTroopsTo(factory.id)..sort((a, b) => a.turns.compareTo(b.turns));
      if (troops.isEmpty)
        return;
      var factoryState = statesHolder.getFactoryAtStep(factory.id, troops.last.turns);
      if (factoryState.isMine())
        return;
      // Send troops from nearest factories to defend the factory.
      var closest = distances.getMinDistances(factory.id, ownWithCyborgs, statesHolder);
      troops.any((troop) {
        var factoryAtTroop = statesHolder.getFactoryAtStep(factory.id, troop.turns);
        if (factoryAtTroop.isMine())
          return false;
        var enemy = factoryAtTroop.cyborgs;
        var cyborgsSent = 0;
        var newGameState = gameState.clone();
        var defenders = [];
        closest.any((info) {
          var cyborgs = min(enemy - cyborgsSent + 1, gameState.getFreeCyborgs(info[0]));
          cyborgsSent += cyborgs;
          if (cyborgs > 0) {
            var path = distances.getPath(info[0], factory.id, statesHolder);
            newGameState.moveTroop(info[0], path['path'][1], cyborgs,
                distances.getDistanceDirect(info[0], path['path'][1]));
            defenders.add('MOVE ${info[0]} ${path['path'][1]} ${cyborgs}; MSG d to ${factory.id}');
          }
          return cyborgsSent > enemy;
        });
        if (defenders.isNotEmpty) {
          statesHolder.invalidateFromState(newGameState, 0);
          gameState = statesHolder.current();
          actions.addAll(defenders);
        }
        return cyborgsSent < enemy;
      });
    });

    return actions;
  }

  List<List<int>> strategyAttack() {
    GameState gameState = statesHolder.current();
    var ownFactories = gameState.getOwnFactoriesWithCyborgs().fold([], (List ids, factory) => ids..add(factory.id));
    var closest = getTargets(ownFactories);
    List<List<int>> move = [];
    closest.forEach((factoryId) {
      gameState = statesHolder.current();
      List<List<dynamic>> attackers = [];
      var newGameState = gameState.clone();
      var closestOurs = distances.getMinDistances(factoryId, ownFactories, statesHolder);
      var i = 0, cyborgsSent = 0, enemyCyborgs = 0;
      while (i < closestOurs.length && cyborgsSent <= enemyCyborgs) {
        var from = closestOurs[i];
        var targetAtStep = statesHolder.getFactoryAtStep(factoryId, from[1] + 1);
        if (targetAtStep.isMine())
          break;
        i++;
        enemyCyborgs = targetAtStep.cyborgs;
        var cyborgs = min(enemyCyborgs - cyborgsSent + 1, newGameState.getFreeCyborgs(from[0]));
        if (cyborgs > 0) {
          var path = distances.getPath(from[0], factoryId, statesHolder)['path'];
          // Don't move to factory at the same time when bomb will arrive.
          if (statesHolder.getStep(from[1]).bombs.values.any((b) => b.factoryTo == factoryId && path.length == 2 &&
              b.turns == 1))
            continue;
          cyborgsSent += cyborgs;
          // TODO: check correct turn
          newGameState.moveTroop(from[0], path[1], cyborgs, distances.getDistanceDirect(from[0], path[1]));
          attackers.add([from[0], path[1], cyborgs, 'to ${factoryId}']);
        }
      }
      if (cyborgsSent > enemyCyborgs) {
        move.addAll(attackers);
        statesHolder.invalidateFromState(newGameState, 0);
      }
    });

    return move;
  }

  List<String> strategyIncrease() {
    List<String> actions = [];
    GameState gameState = statesHolder.current();
    gameState.getOwnFactoriesWithCyborgs().forEach((factory) {
      if (factory.production == 3 || gameState.getFreeCyborgs(factory.id) < 10)
        return;
      actions.add('INC ${factory.id}');
      gameState.factories[factory.id].cyborgs -= 10;
      statesHolder.invalidateFromState(gameState);
    });
    return actions;
  }

  List<String> strategyRemains() {
    List<String> actions = [];
    GameState gameState = statesHolder.current();
    var enemyFactories = gameState.factories.values.where((f) => f.isOpponent()).map((f) => f.id).toList();
    if (enemyFactories.isEmpty)
      return actions;
    var ownFactories = gameState.factories.values.where((f) => f.isMine()).map((f) => f.id)
        .toList();

    int closest;
    double distance = double.MAX_FINITE;
    enemyFactories.forEach((fromId) {
      var sum = 0;
      ownFactories.forEach((toId) {
        sum += distances.getPath(fromId, toId, statesHolder)['length'];
      });
      var avg = sum / ownFactories.length - gameState.factories[fromId].cyborgs;
      if (avg < distance) {
        closest = fromId;
        distance = avg;
      }
    });

    gameState.getOwnFactoriesWithCyborgs().forEach((factory) {
      var freeCyborgs = gameState.getFreeCyborgs(factory.id);
      if (freeCyborgs <= 0 || factory.id == closest)
        return;
      var to = distances.getPath(factory.id, closest, statesHolder)['path'][1];
      actions.add('MOVE ${factory.id} ${to} ${freeCyborgs}; MSG r to ${closest}');
      gameState.factories[factory.id].cyborgs -= freeCyborgs;
      statesHolder.invalidateFromState(gameState);
    });
    return actions;
  }

  void _loop() {
    _readEntities();
    Logger.info('loop');
    List<List<int>> bombs = strategyBomb();
    var actions = strategyDefend();
    List<List<int>> move = strategyAttack();
    actions.addAll(strategyIncrease());
    actions.addAll(strategyRemains());
    var toPrint = [];
    if (bombs.isNotEmpty)
      toPrint.addAll(bombs.map((single) => 'BOMB '+single.join(' ')));
    if (move.isNotEmpty)
      toPrint.addAll(move.map((single) => 'MOVE '+single.take(3).join(' ')+'; MSG '+single.removeLast()));
    toPrint.addAll(actions);
    if (toPrint.isEmpty)
      toPrint.add('WAIT');
    toPrint.add('MSG ${watch.elapsedMilliseconds} ms');
    print(toPrint.join(';'));
    Logger.info('elapsed: ${watch.elapsedMilliseconds}');
    Logger.debug('end');
  }
}

class StatesHolder {
  List<GameState> states = [];
  int id = 0;

  StatesHolder(GameState state) {
    states.add(state);
  }

  GameState current() {
    return states[0];
  }

  GameState _getStateAtStep(int step) {
    for (var i = 0; i <= step; i++) {
      if (states.length - 1 < i)
        _getNextState(states[i-1]);
      if (i == step)
        return states[i];
    }
    throw new Exception('Should return step ${step}');
  }

  GameState _getNextState(GameState gameState) {
    int step = states.indexOf(gameState);
    if (states.length > step + 1)
      return states[step + 1];
    GameState nextGameState = gameState.clone(true);
    states.add(nextGameState);

    nextGameState.troops.forEach((id, troop) => troop.turns--);
    nextGameState.bombs.forEach((id, bomb) => bomb.turns--);
    nextGameState.factories.forEach((id, factory) {
      factory.disabled -= factory.disabled > 0 ? 1 : 0;
      // Increase cyborgs on factory
      if (!factory.isNeutral() && factory.disabled == 0)
        factory.cyborgs += factory.production;
      // Solve battles
      var myCyborgs = 0, enemyCyborgs = 0;
      List<Troop> participants = nextGameState.troops.values
          .where((Troop troop) => troop.factoryTo == factory.id && troop.turns == 0).toList();
      participants.forEach((troop) {
        if (troop.isMine())
          myCyborgs += troop.cyborgs;
        else
          enemyCyborgs += troop.cyborgs;
        nextGameState.troops.remove(troop.id);
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
      List<Bomb> toExplode = nextGameState.bombs.values
          .where((Bomb bomb) => bomb.factoryTo == factory.id && bomb.turns == 0).toList();
      toExplode.forEach((bomb) {
        factory.cyborgs = max(0, factory.cyborgs - max(10, (factory.cyborgs / 2).ceil()));
        factory.disabled = 5;
        nextGameState.bombs.remove(bomb.id);
      });
    });

    return nextGameState;
  }

  Factory getFactoryAtStep(int id, int step) {
    var state = _getStateAtStep(step);
    return state.factories[id];
  }

  GameState getStep(int step) {
    return _getStateAtStep(step);
  }

  invalidateFromState(GameState state, [int step]) {
    if (step == null)
      step = states.indexOf(state);
    states[step] = state;
    states.removeRange(states.indexOf(state) + 1, states.length);
    id++;
  }
}

class GameState {
  Map<int, Factory> factories = {};
  Map<int, Troop> troops = {};
  Map<int, Bomb> bombs = {};
  Map<int, int> factoryBlock = {};

  /**
   * Clones game state. [asNext] means cloned state will be used as a base for next step, not replacement of current
   * one.
   */
  GameState clone([bool asNext = false]) {
    GameState gameState = new GameState();
    gameState.factories = cloneMapOfClonables(factories);
    gameState.troops = cloneMapOfClonables(troops);
    gameState.bombs = cloneMapOfClonables(bombs);
    gameState.factoryBlock = asNext ? {} : new Map.from(factoryBlock);
    return gameState;
  }

  int _newEntityId(Map<int, dynamic> entities) {
    var ids = entities.keys.toList();
    ids.sort();
    return ids.length > 0 ? ids.last + 1 : 0;
  }

  getFreeCyborgs(int id) {
    return factoryBlock[id] == null ? factories[id].cyborgs : factories[id].cyborgs - factoryBlock[id];
  }

  blockCyborgs(int factoryId, int amount) {
    factoryBlock[factoryId] ??= 0;
    factoryBlock[factoryId] += amount;
  }

  addBomb(int factoryFrom, int factoryTo, int turns) {
    var id = _newEntityId(bombs);
    bombs[id] = new Bomb(id, 1, factoryFrom, factoryTo, turns, true);
  }

  moveTroop(int factoryFrom, int factoryTo, int cyborgs, int turns) {
    var id = _newEntityId(troops);
    factories[factoryFrom].cyborgs -= cyborgs;
    if (factories[factoryFrom].cyborgs < 0)
      throw new Exception('Moving more than have (${cyborgs}) from ${factoryFrom} to ${factoryTo}');
    troops[id] = new Troop(id, 1, factoryFrom, factoryTo, cyborgs, turns, true);
  }

  getOwnCyborgsCount() {
    return factories.values.fold(0, (sum, factory) => sum + (factory.isMine() ? factory.cyborgs : 0));
  }

  List<Troop> getEnemyTroopsTo(int factoryId) {
    return troops.values.where((troop) => troop.factoryTo == factoryId && !troop.isMine()).toList();
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
    return factories.values.where((factory) => !factory.isMine()).toList();
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
    return factories.values.where((factory) => factory.isOpponent() && factory.production > 0).toList()
      ..sort((a, b) => b.production.compareTo(a.production));
  }
}

/**
 * Works with distances preprocessing with Floyd-Warshall algorithm.
 */
class Distances {
  List<List<int>> _matrix;
  List<List<int>> _init;
  List<List<int>> _next;
  Map<StatesHolder, Map<String, Map>> _statePathCache = {};

  Distances(int size, List<List<int>> distances) {
    _init = new List(size);
    _next = new List(size);
    distances.forEach((distance) {
      if (_init[distance[0]] == null)
        _init[distance[0]] = new List(size);
      if (_init[distance[1]] == null)
        _init[distance[1]] = new List(size);
      if (_next[distance[0]] == null)
        _next[distance[0]] = new List(size);
      if (_next[distance[1]] == null)
        _next[distance[1]] = new List(size);
      _init[distance[0]][distance[1]] = distance[2];
      _init[distance[1]][distance[0]] = distance[2];
      _next[distance[0]][distance[1]] = distance[1];
      _next[distance[1]][distance[0]] = distance[0];
    });
    for (var i = 0; i < _init.length; i++) {
      _init[i][i] = 0;
    }

    _doItFloyd(cloneListOfLists(_init));
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

  int getDistanceDirect(int from, int to) {
    return _init[from][to];
  }

  Map getPath(int i, int j, StatesHolder statesHolder, [bool isEnemy = false]) {
    if (i == j)
      throw new Exception('i == j == ${i}');
    var cacheKey = '${statesHolder.hashCode} ${statesHolder.id} ${isEnemy}';
    if (_statePathCache[cacheKey] == null)
      _statePathCache[cacheKey] = {};
    if (_statePathCache[cacheKey]['${i} ${j}'] != null)
      return _statePathCache[cacheKey]['${i} ${j}'];
    List<int> path = [i];
    int current = i, length = 0, next;
    while (j != current) {
      next = _next[current][j];
      length += _matrix[current][next];
      // Don't try to move via enemy factories with cyborgs
      var factory = statesHolder.getFactoryAtStep(next, length);
      if ((!isEnemy && !factory.isMine() || isEnemy && !factory.isOpponent()) && factory.cyborgs > 0) {
        length -= _matrix[current][next];
        length += _init[path.last][j];
        path.add(j);
        break;
      }
      path.add(next);
      current = next;
    }
    _statePathCache[cacheKey]['${i} ${j}'] = {'length': length, 'path': path};
    return _statePathCache[cacheKey]['${i} ${j}'];
  }

  /**
   * Returns max distance from each [to] to other vertices.
   */
  Map<int, int> getMaxDistancesTo(List<int> to, StatesHolder statesHolder) {
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

  /**
   * Get a list of closest vertices among [from] to [to] with checking enemy vertices on the path.
   */
  List<List<int>> getMinDistances(int to, List<int> from, StatesHolder statesHolder) {
    Map<int, List<int>> distances = {};
    for (var i = 0; i < _matrix.length; i++) {
      if (to == i || !from.contains(i))
        continue;
      if (distances[i] == null)
        distances[i] = [i, 0];
      distances[i] = [i, max(distances[i][1], getPath(i, to, statesHolder)['length'])];
    }
    List<List<int>> ordered = distances.values.toList()..sort((a, b) => a[1].compareTo(b[1]));

    return ordered;
  }

  /**
   * Get vertex among [from] with minimum distance to each [to].
   */
  int getClosest(List<int> from, List<int> to, StatesHolder statesHolder) {
    int closest;
    double distance = double.MAX_FINITE;
    from.forEach((fromId) {
      var sum = 0;
      to.forEach((toId) {
        sum += getPath(fromId, toId, statesHolder)['length'];
      });
      var avg = sum / to.length;
      if (avg < distance) {
        closest = fromId;
        distance = avg;
      }
    });

    return closest;
  }

  /**
   * Get closest vertex to [to] among [among] w/o checking enemy vertices on the path.
   */
  Map getClosestSimple(int to, List<int> among) {
    int min, closest = 0;
    for (var i = 0; i < _init.length; i++) {
      if (to == i || !among.contains(i))
        continue;
      if (min == null || _init[i][to] < min) {
        min = _init[i][to];
        closest = i;
      }
    }

    return {'id': closest, 'length': min};
  }
}

class Factory {
  int id, owner, cyborgs, production, disabled;

  Factory(this.id, this.owner, this.cyborgs, this.production, this.disabled);

  isMine() => owner == 1;

  isNeutral() => owner == 0;

  isOpponent() => owner == -1;

  currentProduction() => disabled > 0 ? 0 : production;

  Factory clone() => new Factory(id, owner, cyborgs, production, disabled);

  String toString() => [id, owner, cyborgs, production, disabled].join(' ');
}

class Troop {
  int id, owner, cyborgs, turns, factoryFrom, factoryTo;
  bool isNew;

  Troop(this.id, this.owner, this.factoryFrom, this.factoryTo, this.cyborgs, this.turns, this.isNew);

  Troop clone() => new Troop(id, owner, factoryFrom, factoryTo, cyborgs, turns, isNew);

  String toString() => [id, owner, cyborgs, turns, factoryFrom, factoryTo, isNew].join(' ');

  bool isMine() => owner == 1;
}

class Bomb {
  int id, owner, factoryFrom, factoryTo, turns;
  bool isNew;

  Bomb(this.id, this.owner, this.factoryFrom, this.factoryTo, this.turns, this.isNew) {
    factoryTo = factoryTo != -1 ? factoryTo : null;
  }

  Bomb clone() => new Bomb(id, owner, factoryFrom, factoryTo, turns, isNew);

  String toString() => [id, owner, factoryFrom, factoryTo, turns, isNew].join(' ');

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