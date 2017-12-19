/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Fragment shader that adjusts the luminance value based on the input sliders and renders the input texture.
 */

varying highp vec2 texCoordVarying;
precision mediump float;

uniform float lumaThreshold;
uniform float chromaThreshold;
uniform bool  isYUV;
uniform sampler2D SamplerY;
uniform sampler2D SamplerUV;
uniform sampler2D SamplerRGBA;
uniform mat3 colorConversionMatrix;

void main()
{
	mediump vec3 yuv;
	lowp vec3 rgb;
    lowp float r,g,b;
	// Subtract constants to map the video range start at 0

//
    if (isYUV) {
        yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0))* lumaThreshold;
        yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5))* chromaThreshold;
        rgb = colorConversionMatrix * yuv;
        gl_FragColor = vec4(rgb,1);
    } else {
        r = texture2D(SamplerRGBA, texCoordVarying).b;
        g = texture2D(SamplerRGBA, texCoordVarying).g;
        b = texture2D(SamplerRGBA, texCoordVarying).r;
        gl_FragColor = vec4(r,g,b,1);
    }

}
