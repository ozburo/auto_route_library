import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        ExtendedNavigator.root.pop<bool>(false);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FlatButton(
            child: Text("Login"),
            onPressed: () async {
              ExtendedNavigator.of(context).pop<bool>(true);
            },
          ),
        ),
      ),
    );
  }
}
