import 'package:auto_route_generator/route_config_resolver.dart';
import 'package:auto_route_generator/utils.dart';

class RouterClassGenerator {
  final RouterConfig _rootRouterConfig;
  final StringBuffer _stringBuffer = StringBuffer();

  RouterClassGenerator(this._rootRouterConfig);

  // helper functions
  void _write(Object obj) => _stringBuffer.write(obj);

  void _writeln([Object obj]) => _stringBuffer.writeln(obj);

  void _newLine() => _stringBuffer.writeln();

  String generate() {
    var allRouters = _rootRouterConfig.collectAllRoutersIncludingParent;
    var allRoutes = allRouters.fold<List<RouteConfig>>(
        [], (all, e) => all..addAll(e.routes)).toList();
    _generateImports(allRoutes);

    allRouters.forEach((routerConfig) {
      _generateRoutesClass(routerConfig);
      _generateRouterClass(routerConfig);

      if (_rootRouterConfig.generateNavigationHelper) {
        _generateNavigationHelpers(routerConfig);
      }
    });

    _generateArgumentHolders(allRoutes);

    return _stringBuffer.toString();
  }

  void _generateImports(List<RouteConfig> routes) {
    // write route imports
    final imports = {
      "'package:flutter/material.dart'",
      "'package:flutter/cupertino.dart'",
      "'package:auto_route/auto_route.dart'",
    };
    routes.forEach((r) {
      imports.addAll(r.imports);
      if (r.transitionBuilder != null) {
        imports.add(r.transitionBuilder.import);
      }
      if (r.parameters != null) {
        r.parameters.where((p) => p.imports != null).forEach((param) {
          imports.addAll(param.imports);
        });
      }
      if (r.guards != null) {
        r.guards.forEach((g) => imports.add(g.import));
      }
    });
    imports
        .where((import) => import != null)
        .forEach((import) => _writeln('import $import;'));
  }

  void _generateRoutesClass(RouterConfig routerConfig) {
    _writeln('class ${routerConfig.routesClassName} {');
    var allNames = <String>{};
    routerConfig.routes.forEach((r) {
      final routeName = r.name;
      final path = r.pathName;

      if (path.contains(':')) {
        // handle template paths
        _writeln("static const String _$routeName = '$path';");
        allNames.add('_$routeName');
        var params = RegExp(r':([^/]+)')
            .allMatches(path)
            .map((m) => "@required ${m.group(1)}");
        _writeln(
            "static $routeName({${params.join(',')}}) => '${path.replaceAll(':', '\$')}';");
      } else {
        allNames.add(routeName);
        _writeln("static const String $routeName = '$path';");
      }
    });
    _writeln("static const all = <String>{");
    allNames.forEach((name) => _write('$name,'));
    _write("};");
    _writeln('}');
  }

  void _generateRouteTemplates(RouterConfig routerConfig) {
    _newLine();
    routerConfig.routes.forEach((r) {
      _writeln("RouteDef(${routerConfig.routesClassName}.${r.templateName}");
      _writeln(",page: ${r.className}");
      if (r.guards?.isNotEmpty == true) {
        _writeln(",guards:${r.guards.map((e) => e.type).toList().toString()}");
      }
      if (r.routerConfig != null) {
        _writeln(",innerRouter: () => ${r.routerConfig.routerClassName}(),");
      }
      _writeln('),');
    });
  }

  void _generateRouteGeneratorFunction(RouterConfig routerConfig) {
    _newLine();

    var routesMap = <String, RouteConfig>{};
    routerConfig.routes.forEach((route) {
      routesMap[route.className] = route;
    });

    routesMap.forEach((name, route) {
      _writeln('$name: (RouteData data) {');
      _generateRoute(route);
      //close builder
      _write("},");
    });
  }

  void _generateRoute(RouteConfig r) {
    List constructorParams = [];

    if (r.parameters?.isNotEmpty == true) {
      // if router has any required or positional params the argument class holder becomes required.
      final nullOk = !r.argParams.any((p) => p.isRequired || p.isPositional);
      // show an error page  if passed args are not the same as declared args

      if (r.argParams.isNotEmpty) {
        final argsType = r.argumentsHolderClassName;
        _writeln('var args = data.getArgs<$argsType>(');
        if (!nullOk) {
          _write('nullOk: false');
        } else {
          _write("orElse: ()=> $argsType()");
        }
        _write(");");
      }
      constructorParams = r.parameters.map<String>((param) {
        String getterName;
        if (param.isPathParam) {
          getterName =
              "data.pathParams['${param.paramName}'].${param.getterName}${param.defaultValueCode != null ? '?? ${param.defaultValueCode}' : ''}";
        } else if (param.isQueryParam) {
          getterName =
              "data.queryParams['${param.paramName}'].${param.getterName}${param.defaultValueCode != null ? '?? ${param.defaultValueCode}' : ''}";
        } else {
          getterName = "args.${param.name}";
        }
        if (param.isPositional) {
          return getterName;
        } else {
          return '${param.name}:$getterName';
        }
      }).toList();
    }

    // add any empty item to add a comma at end
    // when join(',') is called
    if (constructorParams.length > 2) {
      constructorParams.add('');
    }
    final constructor =
        "${r.className}(${constructorParams.join(',')})${r.hasWrapper ? ".wrappedRoute(context)" : ""}";

    _generateRouteBuilder(r, constructor);
  }

  void _generateArgumentHolders(List<RouteConfig> routes) {
    final routesWithArgsHolders = Map<String, RouteConfig>();

    // make sure we only generated holder classes for
    // routes with parameters
    // also prevent duplicate class with the same name from being generated;

    routes
        .where((r) => r.argParams.isNotEmpty)
        .forEach((r) => routesWithArgsHolders[r.className] = r);

    if (routesWithArgsHolders.isNotEmpty) {
      _generateBoxed('Arguments holder classes');
      routesWithArgsHolders.values.forEach(_generateArgsHolder);
    }
  }

  void _generateArgsHolder(RouteConfig r) {
    _writeln('//${r.className} arguments holder class');
    final argsClassName = '${r.argumentsHolderClassName}';

    // generate fields
    _writeln('class $argsClassName{');
    final params = r.argParams;
    params.forEach((param) {
      _writeln('final ${param.type} ${param.name};');
    });

    // generate constructor
    _writeln('$argsClassName({');
    params.asMap().forEach((i, param) {
      if (param.isRequired || param.isPositional) {
        _write('@required ');
      }

      _write('this.${param.name}');
      if (param.defaultValueCode != null) {
        _write(' = ${param.defaultValueCode}');
      }
      if (i != params.length - 1) {
        _write(',');
      }
    });
    _writeln('});');
    _writeln('}');
  }

  void _generateBoxed(String message) {
    _writeln('\n// '.padRight(77, '*'));
    _writeln('// $message');
    _writeln('// '.padRight(77, '*'));
    _newLine();
  }

  void _generateRouterClass(RouterConfig routerConfig) {
    _writeln('\nclass ${routerConfig.routerClassName} extends RouterBase {');

//    _generateOverrideFunctions(routerConfig);
    _writeln('''
     @override
     List<RouteDef> get routes => _routes;
     final _routes = <RouteDef>[
     ''');
    _generateRouteTemplates(routerConfig);
    _write('];');

    _writeln('''
       @override
       Map<Type, AutoRouteFactory> get pagesMap => _pagesMap;
        final _pagesMap = <Type, AutoRouteFactory>{
        ''');
    _generateRouteGeneratorFunction(routerConfig);
    _write('};');

    // close router class
    _writeln('}');
  }

  void _generateOverrideFunctions(RouterConfig routerConfig) {
    final routesWithGuards = routerConfig.routes
        .where((r) => r.guards != null && r.guards.isNotEmpty);

    if (routesWithGuards.isNotEmpty) {
      _writeln('\n@override');
      _writeln('Map<String, List<Type>> get guardedRoutes => const {');
      routesWithGuards.forEach((r) {
        _write(
            '${routerConfig.routesClassName}.${r.templateName}:${r.guards.map((g) => g.type).toSet().toList()},');
      });
      _write('};');
    }

    var parentRoutes = routerConfig.routes.where((r) => r.routerConfig != null);
    if (parentRoutes.isNotEmpty) {
      _writeln('\n@override');
      _writeln('Map<String, RouterBuilder > get subRouters => {');
      parentRoutes.forEach((route) {
        _writeln(
            "${routerConfig.routesClassName}.${route.templateName}: () => ${route.routerConfig.routerClassName}(),");
      });
      _writeln("};");
    }
  }

  void _generateRouteBuilder(RouteConfig r, String constructor) {
    final returnType = r.returnType ?? 'dynamic';
    if (r.routeType == RouteType.cupertino) {
      _write(
          'return CupertinoPageRoute<$returnType>(builder: (context) => $constructor, settings: data,');
      if (r.cupertinoNavTitle != null) {
        _write("title:'${r.cupertinoNavTitle}',");
      }
    } else if (r.routeType == RouteType.material) {
      _write(
          'return MaterialPageRoute<$returnType>(builder: (context) => $constructor, settings: data,');
    } else if (r.routeType == RouteType.adaptive) {
      _write(
          'return buildAdaptivePageRoute<$returnType>(builder: (context) => $constructor, settings: data,');
      if (r.cupertinoNavTitle != null) {
        _write("cupertinoTitle:'${r.cupertinoNavTitle}',");
      }
    } else {
      _write(
          'return PageRouteBuilder<$returnType>(pageBuilder: (context, animation, secondaryAnimation) => $constructor, settings: data,');

      if (r.customRouteOpaque != null) {
        _write('opaque:${r.customRouteOpaque.toString()},');
      }
      if (r.customRouteBarrierDismissible != null) {
        _write(
            'barrierDismissible:${r.customRouteBarrierDismissible.toString()},');
      }
      if (r.transitionBuilder != null) {
        _write('transitionsBuilder: ${r.transitionBuilder.name},');
      }
      if (r.durationInMilliseconds != null) {
        _write(
            'transitionDuration: const Duration(milliseconds: ${r.durationInMilliseconds}),');
      }
    }
    // generated shared props
    if (r.fullscreenDialog != null) {
      _write('fullscreenDialog:${r.fullscreenDialog.toString()},');
    }
    if (r.maintainState != null) {
      _write('maintainState:${r.maintainState.toString()},');
    }

    _writeln(');');
  }

  void _generateNavigationHelpers(RouterConfig routerConfig) {
    _generateBoxed('Navigation helper methods extension');
    _writeln(
        'extension ${routerConfig.routerClassName}NavigationHelperMethods on ExtendedNavigatorState {');
    for (var route in routerConfig.routes) {
      // skip routes that has path or query params until
      // until there's a practical way to handle them
      if (route.parameters
              ?.any((param) => param.isPathParam || param.isQueryParam) ==
          true) {
        continue;
      }
      _generateHelperMethod(route, routerConfig.routesClassName);
    }
    _writeln('}');
  }

  void _generateHelperMethod(RouteConfig route, String routesClassName) {
    final genericType = route.returnType == null ? '' : '<${route.returnType}>';
    _write('Future$genericType push${capitalize(route.name)}(');
    // generate constructor
    if (route.parameters != null) {
      _write('{');
      route.parameters.forEach((param) {
        if (param.isRequired || param.isPositional) {
          _write('@required ');
        }

        _write('${param.type} ${param.name}');
        if (param.defaultValueCode != null) {
          _write(' = ${param.defaultValueCode}');
        }
        _write(',');
      });
      if (route.guards?.isNotEmpty == true) {
        _write('OnNavigationRejected onReject');
      }
      _write('}');
    }
    _writeln(')');
    _write(' => pushNamed$genericType($routesClassName.${route.name}');
    if (route.parameters != null) {
      _write(',arguments: ');
      _write('${route.argumentsHolderClassName}(');
      _write(route.parameters.map((p) => '${p.name}: ${p.name}').join(','));
      _write('),');

      if (route.guards?.isNotEmpty == true) {
        _write('onReject:onReject,');
      }
    }
    _writeln(');\n');
  }
}
