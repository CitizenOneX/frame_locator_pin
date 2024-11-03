import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frame_imu/compass_heading.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_frame_app/rx/imu.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/code.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

import 'magnetometer_calibrator.dart';

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
  bool _calibrating = false;
  double _calibrationProgress = 0.0;

  // magnetometer outputs need to be calibrated/zeroed with offsets
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _offsetZ = 0.0;
  // different locations on Earth need heading adjusted due to varying magnetic declination
  double _declination = 0.0;
  String _headingText = '';

  final TextEditingController _offsetXController = TextEditingController();
  final TextEditingController _offsetYController = TextEditingController();
  final TextEditingController _offsetZController = TextEditingController();
  final TextEditingController _declinationController = TextEditingController();


  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();

    _loadPrefs();
  }

  @override
  Future<void> run() async {
    setState(() {
      currentState = ApplicationState.running;
    });

    try {
      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU().attach(frame!.dataResponse).listen((imuData) async {
        _log.info(() => 'Raw: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        // apply offsets learned through calibration
        final calibratedX = imuData.compass.$1 + _offsetX;
        final calibratedY = imuData.compass.$2 + _offsetY;
        final calibratedZ = imuData.compass.$3 + _offsetZ;

        // accelerometer is configured so that ±2g maps to ±8192, so normalize to 1g == 1.0
        const accelFactor = 4096.0;
        final normAccelX = imuData.accel.$1 / accelFactor;
        final normAccelY = imuData.accel.$2 / accelFactor;
        final normAccelZ = imuData.accel.$3 / accelFactor;
        _log.info(() => 'Calibrated: compass: (${calibratedX.toStringAsFixed(1)}, ${calibratedY.toStringAsFixed(1)}, ${calibratedZ.toStringAsFixed(1)}), accel: (${normAccelX.toStringAsFixed(1)}, ${normAccelY.toStringAsFixed(1)}, ${normAccelZ.toStringAsFixed(1)}), pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        final heading = CompassHeading.calculateTiltCompensatedHeading(
          magX: calibratedX,
          magY: calibratedY,
          magZ: calibratedZ,
          accelX: normAccelX,
          accelY: normAccelY,
          accelZ: normAccelZ);

        // Optionally apply magnetic declination for your location
        // (look up declination for your location: https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml)
        final trueHeading = CompassHeading.applyDeclination(heading, _declination);

        // Get cardinal direction
        final cardinal = CompassHeading.degreesToCardinal(trueHeading);

        setState(() {
          _headingText = 'Heading: ${trueHeading.toStringAsFixed(1)}° $cardinal';
        });

        _log.info(_headingText);
        await frame!.sendMessage(TxPlainText(msgCode: 0x12, text: _headingText));
      });

      // kick off the frameside IMU streaming
      await frame!.sendMessage(TxCode(msgCode: 0x40, value: 1)); // START_IMU_MSG, 1 per second

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

  /// Additional calibration function to run before regular app mode
  Future<void> _runCalibration() async {
    setState(() {
      currentState = ApplicationState.running;
      _calibrating = true;
    });

    try {
      final calibrator = MagnetometerCalibrator();

      // Listen for calibration completion and cancel IMU stream, return to Ready
      calibrator.onCalibrationComplete.listen((offsets) async {
        _offsetX = offsets['offsetX']!;
        _offsetY = offsets['offsetY']!;
        _offsetZ = offsets['offsetZ']!;
        _log.info('Calibration complete! Offsets: ($_offsetX, $_offsetY. $_offsetZ)');
        _offsetXController.text = _offsetX.toStringAsFixed(2);
        _offsetYController.text = _offsetY.toStringAsFixed(2);
        _offsetZController.text = _offsetZ.toStringAsFixed(2);

        // cancel the frameside IMU streaming
        await frame!.sendMessage(TxCode(msgCode: 0x41)); // STOP_IMU_MSG

        setState(() {
          currentState = ApplicationState.ready;
          _calibrating = false;
        });
      });

      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU().attach(frame!.dataResponse).listen((imuData) {
        _log.info('Calibration IMU data: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');
        // feed the samples into the calibrator
        calibrator.addSample(imuData.compass.$1.toDouble(), imuData.compass.$2.toDouble(), imuData.compass.$3.toDouble());
        setState(() {
          _calibrationProgress = calibrator.getProgress();
        });
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
  void dispose() async {
    await imuStreamSubs?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _offsetXController.text = prefs.getString('offsetX') ?? '0.0';
      _offsetYController.text = prefs.getString('offsetY') ?? '0.0';
      _offsetZController.text = prefs.getString('offsetZ') ?? '0.0';
      _offsetX = double.parse(_offsetXController.text);
      _offsetY = double.parse(_offsetYController.text);
      _offsetZ = double.parse(_offsetZController.text);

      _declinationController.text = prefs.getString('declination') ?? '0.0';
      _declination = double.parse(_declinationController.text);
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offsetX', _offsetXController.text);
    await prefs.setString('offsetY', _offsetYController.text);
    await prefs.setString('offsetZ', _offsetZController.text);
    await prefs.setString('declination', _declinationController.text);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Frame IMU Demo',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Frame IMU Demo'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _offsetXController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'offset:X-axis', hintText: 'Magnetometer offset - X axis'),),
                TextField(
                  controller: _offsetYController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'offset:Y-axis', hintText: 'Magnetometer offset - Y axis'),),
                TextField(
                  controller: _offsetZController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'offset:Z-axis', hintText: 'Magnetometer offset - Z axis'),),
                TextField(
                  controller: _declinationController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'magnetic declination for your latitude/longitude', hintText: 'Magnetic Declination Estimate'),),
                ElevatedButton(onPressed: _runCalibration, child: const Text('Calibrate Magnetometer')),
                if (_calibrating) LinearProgressIndicator(value: _calibrationProgress),
                const Divider(),
                ElevatedButton(onPressed: _savePrefs, child: const Text('Save')),
                const SizedBox(height: 24),
                if (currentState == ApplicationState.running) Text(_headingText, style: const TextStyle(fontSize: 24)),
                const Spacer(),
              ],
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.north_east), const Icon(Icons.cancel)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
