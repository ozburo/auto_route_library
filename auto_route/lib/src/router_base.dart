part of 'extended_navigator.dart';

typedef AutoRouteFactory = Route<dynamic> Function(RouteData data);
typedef RouterBuilder<T extends RouterBase> = T Function();

abstract class RouterBase {
  List<RouteDef> get routes;

  Map<Type, AutoRouteFactory> get pagesMap;

  Set<String> get allRoutes => routes.map((e) => e.template).toSet();

  Route<dynamic> onGenerateRoute(RouteSettings settings, [String basePath]) {
    assert(routes != null);
    assert(settings != null);
    var match = findFullMatch(settings);
    if (match != null) {
      var namePrefix = basePath?.isNotEmpty == true ? "$basePath" : '';
      var matchResult =
          match.copyWith(name: "$namePrefix${settings.name}") as RouteMatch;
      RouteData data;
      if (matchResult.isParent) {
        data = _ParentRouteData(
          matchResult: matchResult,
          initialRoute: matchResult.restAsString,
          router: matchResult.routeDef.innerRouter(),
        );
      } else {
        data = RouteData(matchResult);
      }
      return pagesMap[matchResult.routeDef.page](data);
    }
    return null;
  }

  // a shorthand for calling the onGenerateRoute function
  // when using Router directly in MaterialApp or such
  // Router().onGenerateRoute becomes Router()
  Route<dynamic> call(RouteSettings settings) => onGenerateRoute(settings);

  RouteMatch findFullMatch(RouteSettings settings) {
    // deep links are  pre-matched
    if (settings is RouteMatch) {
      return settings;
    } else {
      var matcher = RouteMatcher(settings);
      for (var route in routes) {
        var match = matcher.match(route, fullMatch: true);
        if (match != null) {
          return match;
        }
      }
    }
    return null;
  }

  List<RouteMatch> allMatches(RouteMatcher matcher) {
    var matches = <RouteMatch>[];
    for (var route in routes) {
      var matchResult = matcher.match(route);
      if (matchResult != null) {
        matches.add(matchResult);
        if (matchResult.isParent || !matchResult.hasRest) {
          break;
        }
      }
    }
    return matches;
  }
}
