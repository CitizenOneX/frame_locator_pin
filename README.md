# Frame Augmented Reality (AR) Live Location Pin Demo

Overlays AR location / navigation pins representing multiple points of interest (POIs) into the field of view. Uses Frame's onboard magnetometer and accelerometer data streamed to the phone to calculate and update the bearing to each POI. Uses accelerometer pitch as a last-moment vertical adjustment prior to the draw call - a hybrid approach to give a slightly more responsive feel.

Currently uses hard-coded sample latitude/longitude coordinates for the current user position and two sample POIs for the purposes of the demo. (Using the phone's GPS for the current user location, and a mapping service to search for and get coordinates of points of interest - or a friend's live location - is left as an exercise.)

Each POI can have a different icon (PNGs are in assets/sprites), color and text label.

### Frameshot

![Frameshot1](docs/frameshot1.png)

### Framecast
