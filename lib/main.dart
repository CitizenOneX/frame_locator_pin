import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frame_locator_pin/tx/multi_poi.dart';
import 'package:logging/logging.dart';
import 'package:simple_frame_app/rx/imu.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/code.dart';

import 'calculator.dart';
import 'compass_heading.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  StreamSubscription<IMUData>? imuStreamSubs;

  // magnetometer outputs need to be calibrated/zeroed with offsets
  static const double _offsetX = -1112.5;
  static const double _offsetY = -450.5;
  static const double _offsetZ = -6855.0;

  // different locations on Earth need heading adjusted due to varying magnetic declination
  static const double _declination = 12.8;
  double _trueHeading = 0.0;
  String _headingText = '';

  // accelerometer outputs get normalised to 1.0 == 1g
  static const int accelFactor = 4096;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  Future<void> run() async {
    setState(() {
      currentState = ApplicationState.running;
    });

    try {
      // set up some sample locations.
      // If sampling the GPS, this should go inside the IMU streaming handler.
      // For fixed sample location this is fine though.
      final currentLocation = GPSCoordinate(
        latitude: -53.796173,
        longitude: 121.1773106,
      );

      // one nearby location, use the favorite icon
      final favLocation = GPSCoordinate(
        latitude: -53.795722,
        longitude: 121.1775937,
      );

      // another nearby location, use the bank icon
      final bankLocation = GPSCoordinate(
        latitude: -53.791576,
        longitude: 121.1849747,
      );

      // create an ARCalculator suitable for mapping bearings to pixels on the Frame display
      var calc = ARCalculator(iconWidth: 64, arrowWidth: 16, maxRelativeAngle: 90.0);

      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU(smoothingSamples: 5).attach(frame!.dataResponse).listen((imuData) async {
        _log.fine(() => 'Raw: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        // apply offsets learned through calibration
        final calibMagX = imuData.compass.$1 + _offsetX;
        final calibMagY = imuData.compass.$2 + _offsetY;
        final calibMagZ = imuData.compass.$3 + _offsetZ;

        // accelerometer is configured so that ±2g maps to ±8192,
        // so normalize to 1g == 1.0
        var normAccelX = imuData.accel.$1 / accelFactor;
        var normAccelY = imuData.accel.$2 / accelFactor;
        var normAccelZ = imuData.accel.$3 / accelFactor;

        // normalize to an overall magnitude of 1g
        double normAccel = math.sqrt(normAccelX * normAccelX + normAccelY * normAccelY + normAccelZ * normAccelZ);
        normAccelX /= normAccel;
        normAccelY /= normAccel;
        normAccelZ /= normAccel;

        _log.fine(() => 'Calibrated: compass: (${calibMagX.toStringAsFixed(1)}, ${calibMagY.toStringAsFixed(1)}, ${calibMagZ.toStringAsFixed(1)}), accel: (${normAccelX.toStringAsFixed(1)}, ${normAccelY.toStringAsFixed(1)}, ${normAccelZ.toStringAsFixed(1)}), pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        final magHeading = CompassHeading.calculateTiltCompensatedHeading(
          magX: calibMagX,
          magY: calibMagY,
          magZ: calibMagZ,
          gravityX: normAccelX,
          gravityY: normAccelY,
          gravityZ: normAccelZ);

        // Optionally apply magnetic declination for your location
        // (look up declination for your location: https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml)
        _trueHeading = CompassHeading.applyDeclination(magHeading, _declination);

        // Get cardinal direction for display e.g. 'ENE'
        final cardinal = CompassHeading.degreesToCardinal(_trueHeading);

        // Show the direction of our sample targets from our sample current position
        final favPosition = calc.calculateIconPosition(
          currentLocation: currentLocation,
          targetLocation: favLocation,
          compassHeading: _trueHeading * math.pi / 180,
        );

        // Show the direction of our sample targets from our sample current position
        final bankPosition = calc.calculateIconPosition(
          currentLocation: currentLocation,
          targetLocation: bankLocation,
          compassHeading: _trueHeading * math.pi / 180,
        );

        setState(() {
          _headingText = 'Heading: ${_trueHeading.toStringAsFixed(1)}° $cardinal';
        });

        _log.fine(_headingText);

        await frame!.sendMessage(
          TxMultiPoi(
            msgCode: 0x50,
            pois: [
              Poi(spriteCode: 0x20, x: favPosition.x, paletteOffset: 12, label: '${favPosition.distance.toStringAsFixed(0)}m'),
              Poi(spriteCode: 0x21, x: bankPosition.x, paletteOffset: 7, label: '${bankPosition.distance.toStringAsFixed(0)}m'),
            ]));
      });

      // kick off the frameside IMU streaming
      await frame!.sendMessage(TxCode(msgCode: 0x40, value: 10)); // START_IMU_MSG, 10 per second

    } catch (e) {
      _log.severe(() => 'Error executing application logic: $e');
      setState(() {
        currentState = ApplicationState.ready;
      });
    }
  }

  @override
  Future<void> cancel() async {
    // cancel the frameside IMU streaming
    await frame!.sendMessage(TxCode(msgCode: 0x41)); // STOP_IMU_MSG

    setState(() {
      currentState = ApplicationState.ready;
    });
  }

  @override
  void dispose() async {
    await imuStreamSubs?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Locator Pin Demo',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
            title: const Text('Frame Locator Pin Demo'),
            actions: [getBatteryWidget()]
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (currentState == ApplicationState.running)
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_headingText, style: const TextStyle(fontSize: 24)),
                  ]
                ),),
              //const Spacer(),
            ],
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.north_east), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
