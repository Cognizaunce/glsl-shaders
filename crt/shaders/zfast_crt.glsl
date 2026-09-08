/*
    zfast_crt_standard - A simple, fast CRT shader.

    Copyright (C) 2017 Greg Hogan (SoltanGris42)

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.


Notes:  This shader does scaling with a weighted linear filter for adjustable
	sharpness on the x and y axes based on the algorithm by Inigo Quilez here:
	http://www.iquilezles.org/www/articles/texture/texture.htm
	but modified to be somewhat sharper.  Then a scanline effect that varies
	based on pixel brighness is applied along with a monochrome aperture mask.
	This shader runs at 60fps on the Raspberry Pi 3 hardware at 2mpix/s
	resolutions (1920x1080 or 1600x1200).
*/

// Parameter lines go here:
#pragma parameter BLURSCALEX "Blur Amount X-Axis" 0.30 0.0 1.0 0.05
#pragma parameter LOWLUMSCAN "Scanline Darkness - Low" 6.0 0.0 10.0 0.5
#pragma parameter HILUMSCAN "Scanline Darkness - High" 8.0 0.0 50.0 1.0
#pragma parameter BRIGHTBOOST "Dark Pixel Brightness Boost" 1.25 0.5 1.5 0.05
#pragma parameter SCAN_FADE "Scanline Fade" 0.8 0.0 1.0 0.05
#pragma parameter VSEP_STRENGTH "Vertical Separation Strength" 0.2 0.0 1.0 0.05
#pragma parameter VSEP_WIDTH "Vertical Separation Width" 0.18 0.02 0.60 0.02

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
#define COMPAT_PRECISION highp
#else
#define COMPAT_PRECISION mediump
#endif
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;
COMPAT_VARYING float maskFade;
COMPAT_VARYING vec2 invDims;
COMPAT_VARYING float vsepScale;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform COMPAT_PRECISION vec2 OutputSize;

#ifdef PARAMETER_UNIFORM
// All parameter floats need to have COMPAT_PRECISION in front of them
uniform COMPAT_PRECISION float SCAN_FADE;
#else
#define SCAN_FADE 0.8
#endif

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
	
	TEX0.xy = TexCoord.xy*1.0001;
	maskFade = 0.3333*SCAN_FADE;
	invDims = 1.0/TextureSize.xy;
	vsepScale = OutputSize.x*invDims.x;
}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#ifdef GL_FRAGMENT_PRECISION_HIGH
#define COMPAT_PRECISION highp
#else
#define COMPAT_PRECISION mediump
#endif
#else
#define COMPAT_PRECISION
#endif

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out COMPAT_PRECISION vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

uniform COMPAT_PRECISION vec2 TextureSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
COMPAT_VARYING float maskFade;
COMPAT_VARYING vec2 invDims;
COMPAT_VARYING float vsepScale;

// compatibility #defines
#define Source Texture
#define vTexCoord TEX0.xy

#ifdef PARAMETER_UNIFORM
// All parameter floats need to have COMPAT_PRECISION in front of them
uniform COMPAT_PRECISION float BLURSCALEX;
uniform COMPAT_PRECISION float LOWLUMSCAN;
uniform COMPAT_PRECISION float HILUMSCAN;
uniform COMPAT_PRECISION float BRIGHTBOOST;
uniform COMPAT_PRECISION float VSEP_STRENGTH;
uniform COMPAT_PRECISION float VSEP_WIDTH;
#else
#define BLURSCALEX 0.3
#define LOWLUMSCAN 6.0
#define HILUMSCAN 8.0
#define BRIGHTBOOST 1.25
#define VSEP_STRENGTH 1.0
#define VSEP_WIDTH 0.18
#endif

void main()
{
	// Shared coordinates: source-pixel position, center, and offset from center.
	COMPAT_PRECISION vec2 p = vTexCoord * TextureSize;
	COMPAT_PRECISION vec2 i = floor(p) + 0.50;
	COMPAT_PRECISION vec2 f = p - i;

	// This is just like "Quilez Scaling" but sharper
	p = (i + 4.0*f*f*f)*invDims;
	p.x = mix(p.x, vTexCoord.x, BLURSCALEX);
	COMPAT_PRECISION vec3 colour = COMPAT_TEXTURE(Source, p).rgb;

	// Horizontal scanlines: calculate darkness from vertical position.
	COMPAT_PRECISION float Y = f.y*f.y;
	COMPAT_PRECISION float YY = Y*Y;
	COMPAT_PRECISION float scanLineWeight =	BRIGHTBOOST - LOWLUMSCAN*(Y - 2.05*YY);
	COMPAT_PRECISION float scanLineWeightB = 1.0 - HILUMSCAN*(YY - 2.8*YY*Y);

	// Vertical separation: estimate separator coverage of each output pixel.
	COMPAT_PRECISION float distToEdge = 0.5 - abs(f.x);
	COMPAT_PRECISION float maxCoverage = min(1.0, VSEP_WIDTH*vsepScale);
	COMPAT_PRECISION float vsep = clamp(
		(0.5*VSEP_WIDTH - distToEdge)*vsepScale + 0.5,
		0.0, maxCoverage
	);
	COMPAT_PRECISION float vsepWeight = 1.0 - VSEP_STRENGTH*vsep;

	// Apply effects and output final color.
	FragColor.rgba = vec4(
		colour.rgb *
		mix(scanLineWeight, scanLineWeightB, dot(colour.rgb, vec3(maskFade))) *
		vsepWeight,
		1.0
	);
} 
#endif
