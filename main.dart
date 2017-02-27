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
  List<List<int>> distances = [];
  GameState gameState;
  StatesHolder statesHolder;

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
    for (var i = 0; i < linkCount; i++) {
      var line = stdin.readLineSync();
      Logger.debug(line);
      distances.add(line.split(' ').map((part) => int.parse(part)).toList());
    }
  }

  void _readEntities() {
    gameState = new GameState();
    statesHolder = new StatesHolder(gameState);
    int entityCount = int.parse(stdin.readLineSync());
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

  List<Factory> getOrderedClosest(List<Factory> to) {
    Map<int, List> closest = {};
    List<Factory> closestFactories = [];
    List toIds = to.fold([], (List ids, factory) => ids..add(factory.id));
    distances.forEach((item) {
      if (!toIds.contains(item[0]) && !toIds.contains(item[1]) || toIds.contains(item[0]) && toIds.contains(item[1]))
        return;
      var id = item[toIds.contains(item[0]) ? 1 : 0];
      if (!closest.containsKey(id))
        closest[id] = [gameState.factories[id], 0];
      if (closest[id][1] < item[2]) {
        closest[id][0] = gameState.factories[id];
        closest[id][1] = item[2];
      }
    });
    closest.values.toList()..sort((a, b) => a[1].compareTo(b[1]))..forEach((item) => closestFactories.add(item[0]));

    return closestFactories;
  }

  int getDistanceBetween(int from, int to) {
    return distances.firstWhere((item) => item[0] == from && item[1] == to || item[1] == from && item[0] == to)[2];
  }

  void _loop() {
    Logger.info('loop');
    _readEntities();
    int freeCyborgs = gameState.getOwnCyborgsCount();
    var cyborgFactories = gameState.getOwnFactoriesWithCyborgs();
    var closest = getOrderedClosest(cyborgFactories);
    var targets = closest.where((factory) {
      var attackers = gameState.getFactoryTroopsComing(factory).fold(0, (sum, troop) => sum + troop.cyborgs);
      var afterFight = factory.cyborgs - attackers;
      var enough = afterFight >= 0 && afterFight < freeCyborgs;
      if (enough)
        freeCyborgs -= afterFight + 1;
      return enough;
    });
    if (targets.isNotEmpty) {
      var moves = [];
      targets.forEach((target) {
        var source = gameState.getMostCyborgFactory();
        if (source.cyborgs == 0)
          return;
        var attackers = gameState.getFactoryTroopsComing(target).fold(0, (sum, troop) => sum + troop.cyborgs);
        var afterFight = gameState.getCyborgsOnStep(getDistanceBetween(target.id, source.id) + 1, target) - attackers;
        if (afterFight < 0)
          return;
        moves.add('MOVE ' + [source.id, target.id, afterFight + 1].join(' '));
      });
      if (moves.isEmpty)
        print('WAIT');
      else
        print(moves.join(';'));
    } else
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
      if (states[i] == null)
        getNextState(states[i-1]);
      if (i == step)
        return states[i];
    }
    throw new Exception('Should return step ${step}');
  }

  GameState getNextState(GameState gameState) {
    int step = states.indexOf(gameState);
    if (states[step + 1] != null)
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
      var participants = troops.values.where((Troop troop) => troop.factoryTo == factory.id && troop.turns == 0);
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
      List<Bomb> toExplode = bombs.values.where((Bomb bomb) => bomb.factoryTo == factory.id && bomb.turns == 0);
      toExplode.forEach((bomb) {
        factory.cyborgs = max(0, factory.cyborgs - max(10, factory.cyborgs / 2));
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
}

class Factory {
  int id, owner, cyborgs, production, disabled;

  Factory(this.id, this.owner, this.cyborgs, this.production, this.disabled);

  isMine() => owner == 1;

  isNeutral() => owner == 0;

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