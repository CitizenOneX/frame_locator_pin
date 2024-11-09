import 'dart:math' as math;

class GPSCoordinate {
  final double latitude;
  final double longitude;

  GPSCoordinate({required this.latitude, required this.longitude});
}

enum IconStyle {
  leftArrow,
  location,
  rightArrow,
}

class DisplayPosition {
  final int x;      // Pixel position (1-640)
  final IconStyle style;  // Icon style based on position
  final double bearing;  // Actual bearing to target in degrees

  DisplayPosition({
    required this.x,
    required this.style,
    required this.bearing,
  });

  @override
  String toString() => 'DisplayPosition(x: $x, style: $style, bearing: ${bearing.toStringAsFixed(1)}°)';
}

class ARCalculator {
  static const int displayWidth = 640;
  static const int displayHeight = 400;
  static const int displayCenterX = displayWidth ~/ 2;
  static const int displayCenterY = displayHeight ~/ 2;
  final int _iconWidth;
  final int _arrowWidth;
  late final double _maxRelativeAngle;
  late final int _minX;
  late final int _maxX;
  late final double _fov;

  ARCalculator({required int iconWidth, required int arrowWidth, double maxRelativeAngle = 90.0}) : _iconWidth = iconWidth, _arrowWidth = arrowWidth {
    _maxRelativeAngle = _toRadians(maxRelativeAngle); // angle to exponentially compress into the FOV
    _minX = _iconWidth ~/ 2 + _arrowWidth + 1;  // 49
    _maxX = displayWidth - (_iconWidth ~/ 2) - _arrowWidth;  // 592
    _fov = (20.0 * (640-(_iconWidth+2*_arrowWidth))/(640)) * math.pi / 180; // perceived full horizontal FOV of the display (i.e., 20° crept in by iconWidth/2+arrowWidth)
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
  static double _toDegrees(double radians) => radians * 180 / math.pi;

  /// returns the bearing (in radians 0..2pi) of target from current
  static double calculateBearing(GPSCoordinate current, GPSCoordinate target) {
    final lat1 = _toRadians(current.latitude);
    final lon1 = _toRadians(current.longitude);
    final lat2 = _toRadians(target.latitude);
    final lon2 = _toRadians(target.longitude);

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
              math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    var bearing = math.atan2(y, x);

    return (bearing + 2 * math.pi) % (2 * math.pi);
  }

  /// Compresses the relative angle into the FOV range using an exponential function
  /// such that +maxRelativeAngle/2 maps to +FOV/2, -maxRelativeAngle/2 maps to -FOV/2
  /// and in the middle smaller values map to angles within the FOV
  /// input and output are in radians, -pi..+pi
  double _compressAngle(double angle) {
    /// Compresses angles non-linearly, mapping:
    /// 0 -> 0
    /// ±pi/4 -> _toRadians(±10°) (edges of Frame display)
    /// Preserves sign and maintains sensitivity near 0
    ///
    /// Args:
    ///   angle: Input angle in radians
    ///
    /// Returns:
    ///   Compressed angle in radians

    // Constants for the exponential function
    // These values were chosen to meet the 45° -> 10° requirement (90° of angle to be compressed into the 20° of display)
    final k = (_fov / 2) / (1 - math.exp(-(_maxRelativeAngle / 2))); // Scaling factor
    const a = 1.0; // Controls the steepness of the curve

    // Handle the sign separately
    final sign = angle.sign;
    final absAngle = angle.abs();

    // Compress using exponential function
    // The function is: k * (1 - exp(-a*x))
    // This gives us 0 at x=0 and approaches k asymptotically
    final compressed = k * (1 - math.exp(-a * absAngle));

    // Restore the sign and return
    return sign * compressed;
  }

  DisplayPosition calculateIconPosition({
    required GPSCoordinate currentLocation,
    required GPSCoordinate targetLocation,
    required double compassHeading}) {

    // Calculate bearing to target
    final targetBearing = calculateBearing(currentLocation, targetLocation);

    // Calculate relative angle (how far target is from current heading)
    var relativeAngle = (targetBearing - compassHeading + math.pi) % (math.pi * 2) - math.pi;

    // compress large relative angles down to get more into the FOV, beyond maxRelativeAngle
    // it still shows a left or right arrow
    relativeAngle = _compressAngle(relativeAngle);

    // Convert angle to pixel position
    // Map from [-fov/2, fov/2] to [1, displayWidth]
    final normalizedX = (relativeAngle + (_fov / 2)) / _fov;
    final rawX = (normalizedX * displayWidth).round();

    // Determine icon style and final position based on calculated position (clamped to edges)
    IconStyle style;
    int x;

    if (rawX <= _minX) {
      style = IconStyle.leftArrow;
      x = _minX;
    } else if (rawX >= _maxX) {
      style = IconStyle.rightArrow;
      x = _maxX;
    } else {
      style = IconStyle.location;
      x = rawX;
    }

    return DisplayPosition(
      x: x,
      style: style,
      bearing: _toDegrees(targetBearing),
    );
  }
}
