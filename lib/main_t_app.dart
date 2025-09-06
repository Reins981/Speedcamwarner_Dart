import 'package:flutter/material.dart';

class MainTApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () => print('Menu button pressed'),
                    child: Text('>>>', style: TextStyle(fontSize: 150)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(153, 153, 153, 0.6),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Night button pressed'),
                    child: Text('Night', style: TextStyle(fontSize: 80)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(179, 179, 179, 0.7),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Info button pressed'),
                    child: Text('Info', style: TextStyle(fontSize: 80)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(173, 173, 173, 0.68),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Map button pressed'),
                    child: Text('Map', style: TextStyle(fontSize: 80)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(166, 166, 166, 0.65),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('POIS button pressed'),
                    child: Text('POIS', style: TextStyle(fontSize: 80)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(158, 158, 158, 0.62),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Start button pressed'),
                    child: Text('Start', style: TextStyle(fontSize: 200)),
                    style: ElevatedButton.styleFrom(
                      primary: Color.fromRGBO(179, 179, 179, 0.7),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Stop button pressed'),
                    child: Text('Stop', style: TextStyle(fontSize: 200)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(153, 153, 153, 0.6),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Exit button pressed'),
                    child: Text('Exit', style: TextStyle(fontSize: 200)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromRGBO(128, 128, 128, 0.5),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => print('Return button pressed'),
                    child: Text('<<<', style: TextStyle(fontSize: 600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
