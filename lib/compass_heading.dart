import 'dart:math';

class CompassHeading {
  // Basic heading calculation without tilt compensation
  static double calculateBasicHeading(double x, double y) {
    // Convert to radians and get heading angle
    final heading = atan2(y, x);

    // Convert to degrees
    var degrees = heading * 180 / pi;

    // Convert to 0-360 range
    if (degrees < 0) {
      degrees += 360;
    }

    return degrees;
  }

  // Tilt-compensated heading calculation
  static double calculateTiltCompensatedHeading({
    required double magX,
    required double magY,
    required double magZ,
    required double accelX,
    required double accelY,
    required double accelZ,
  }) {
    // Calculate pitch and roll from accelerometer data
    final roll = atan2(accelY, accelZ);
    final pitch = atan2(
      -accelX,
      (accelY * sin(roll) + accelZ * cos(roll))
    );

    // Tilt compensation
    final cosRoll = cos(roll);
    final sinRoll = sin(roll);
    final cosPitch = cos(pitch);
    final sinPitch = sin(pitch);

    // Compensate magnetic readings
    final xh = magX * cosPitch +
               magY * sinRoll * sinPitch +
               magZ * cosRoll * sinPitch;

    final yh = magY * cosRoll -
               magZ * sinRoll;

    // Calculate heading
    var heading = atan2(yh, xh);

    // Convert to degrees
    var degrees = heading * 180 / pi;

    // Convert to 0-360 range
    if (degrees < 0) {
      degrees += 360;
    }

    return degrees;
  }

  // Convert heading to cardinal direction
  static String degreesToCardinal(double degrees) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW'
    ];

    // Convert degrees to 16-point compass direction
    var index = ((degrees + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }

  // Apply magnetic declination correction
  static double applyDeclination(double heading, double declination) {
    var correctedHeading = heading + declination;

    if (correctedHeading < 0) {
      correctedHeading += 360;
    } else if (correctedHeading > 360) {
      correctedHeading -= 360;
    }

    return correctedHeading;
  }
}