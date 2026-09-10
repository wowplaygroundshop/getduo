//
//  Shader.metal
//  Fold
//
//  Port of FrostFold.metal to a full-screen fragment pass over a captured desktop.
//
//  Same model, one axis rotated: the desktop lives on a fixed plane, the plane the screen
//  occupied when the lid was open past the clear angle. The viewer does not move. Only the
//  glass moves: as the lid closes by `tilt`, the panel rotates around its bottom edge — the
//  hinge — which stays in the plane, and the rest of the glass rises toward the eye.
//  For each pixel we place it in 3D on the rotated glass, cast a ray from the eye through it
//  onto the desktop plane, and blur around the hit with a radius set by the gap at that pixel.
//  Rays that miss the desktop are black.
//
//  Everything is computed on a virtual canvas 1000 units tall, so one set of tunables works
//  at any resolution and the iOS tuning carries straight over.
//

#include <metal_stdlib>
using namespace metal;

constant int   kBlurTaps    = 32;
constant float kGoldenAngle = 2.39996322972865332;   // radians, Vogel disk spacing
constant float kTwoPi       = 6.28318530717958648;
constant float kCanvas      = 1000.0;

struct Params {
    float2 resolution;      // drawable pixels
    float  tilt;            // radians, 0 = clear
    float  eyeDistance;     // canvas units
    float  blurSpread;
    float  darkening;
    float  baseSeparation;  // canvas units
};

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

vertex float4 foldVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    return float4(p * 2.0 - 1.0, 0.0, 1.0);
}

fragment float4 foldFragment(float4 position [[position]],
                             texture2d<float, access::sample> src [[texture(0)]],
                             constant Params &P [[buffer(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);

    const float2 uv   = position.xy / P.resolution;
    const float2 size = float2(kCanvas * P.resolution.x / P.resolution.y, kCanvas);
    const float2 p    = uv * size;
    const float  tilt = abs(P.tilt);

    if (tilt < 1e-5) {
        return float4(src.sample(smp, uv).rgb, 1.0);
    }

    // The hinge is the bottom edge of the panel. Distance from it drives everything.
    const float  d     = size.y - p.y;
    const float3 glass = float3(p.x, size.y - d * cos(tilt), d * sin(tilt));
    const float3 eye   = float3(size * 0.5, P.eyeDistance);

    const float depth = eye.z - glass.z;
    if (depth <= 1e-3) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    const float  t   = eye.z / depth;
    const float2 hit = eye.xy + (glass.xy - eye.xy) * t;

    const float radius = P.blurSpread * (glass.z + P.baseSeparation);

    if (any(hit < -radius) || any(hit > size + radius)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    const float attenuation = max(1.0 - P.darkening * radius, 0.0);

    if (radius < 0.5) {
        return float4(src.sample(smp, hit / size).rgb * attenuation, 1.0);
    }

    // Vogel disk, rotated per pixel so the tap pattern dithers away instead of banding.
    const int   taps     = clamp(int(radius * 2.0), 6, kBlurTaps);
    const float rotation = hash21(position.xy) * kTwoPi;
    float3 sum = float3(0.0);
    for (int i = 0; i < taps; ++i) {
        const float r = radius * sqrt((float(i) + 0.5) / float(taps));
        const float a = float(i) * kGoldenAngle + rotation;
        sum += src.sample(smp, (hit + r * float2(cos(a), sin(a))) / size).rgb;
    }
    return float4(sum / float(taps) * attenuation, 1.0);
}
