// license:BSD-3-Clause
// copyright-holders:Ryan Holtz,ImJezze
//-----------------------------------------------------------------------------
// Scanline, Shadowmask & Distortion Effect
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Sampler Definitions
//-----------------------------------------------------------------------------

texture DiffuseTexture;

sampler DiffuseSampler = sampler_state
{
	Texture = <DiffuseTexture>;
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	AddressW = CLAMP;
};

texture ShadowTexture;

sampler ShadowSampler = sampler_state
{
	Texture = <ShadowTexture>;
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
	AddressW = WRAP;
};

//-----------------------------------------------------------------------------
// Vertex Definitions
//-----------------------------------------------------------------------------

struct VS_INPUT
{
	float4 Position : POSITION;
	float4 Color : COLOR0;
	float2 TexCoord : TEXCOORD0;
};

struct VS_OUTPUT
{
	float4 Position : POSITION;
	float4 Color : COLOR0;
	float2 SourceCoord : TEXCOORD0;
	float2 TexCoord : TEXCOORD1;
	float2 ScreenCoord : TEXCOORD2;
};

struct PS_INPUT
{
	float4 Color : COLOR0;
	float2 SourceCoord : TEXCOORD0;
	float2 TexCoord : TEXCOORD1;
	float2 ScreenCoord : TEXCOORD2;
};

//-----------------------------------------------------------------------------
// Constants
//-----------------------------------------------------------------------------

static const float PI = 3.1415927f;
static const float PHI = 1.618034f;
static const float Epsilon = 1.0e-7f;
static const float E = 2.7182817f;
static const float Gelfond = 23.140692f; // e^pi (Gelfond constant)
static const float GelfondSchneider = 2.6651442f; // 2^sqrt(2) (Gelfond-Schneider constant)

//-----------------------------------------------------------------------------
// Functions
//-----------------------------------------------------------------------------

// www.stackoverflow.com/questions/5149544/can-i-generate-a-random-number-inside-a-pixel-shader/
float random(float2 seed)
{
	// irrationals for pseudo randomness
	float2 i = float2(Gelfond, GelfondSchneider);

	return frac(cos(dot(seed, i)) * 123456.0f);
}

// www.dinodini.wordpress.com/2010/04/05/normalized-tunable-sigmoid-functions/
float normalizedSigmoid(float n, float k)
{
	// valid for n and k in range of -1.0 and 1.0
	return (n - n * k) / (k - abs(n) * 2.0f * k + 1);
}

// www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
float roundBox(float2 p, float2 b, float r)
{
	return length(max(abs(p) - b + r, 0.0f)) - r;
}

//-----------------------------------------------------------------------------
// Scanline & Shadowmask & Distortion Vertex Shader
//-----------------------------------------------------------------------------

uniform float2 ScreenDims;
uniform float2 SourceDims;
uniform float2 TargetDims;
uniform float2 QuadDims;

uniform float2 ShadowDims = float2(32.0f, 32.0f); // size of the shadow texture (extended to power-of-two size)
uniform float2 ShadowUVOffset = float2(0.0f, 0.0f);

uniform bool SwapXY = false;

uniform bool PrepareBloom = false; // disables some effects for rendering bloom textures
uniform bool VectorScreen = false;

VS_OUTPUT vs_main(VS_INPUT Input)
{
	VS_OUTPUT Output = (VS_OUTPUT)0;

	Output.Position = float4(Input.Position.xyz, 1.0f);
	Output.Position.xy /= ScreenDims;
	Output.Position.y = 1.0f - Output.Position.y; // flip y
	Output.Position.xy -= 0.5f; // center
	Output.Position.xy *= 2.0f; // zoom

	Output.TexCoord = Input.TexCoord;
	Output.TexCoord += PrepareBloom
		? 0.0f / TargetDims  // use half texel offset (DX9) to do the blur for first bloom layer
		: 0.5f / TargetDims; // fix half texel offset correction (DX9)

	Output.ScreenCoord = Input.Position.xy / ScreenDims;

	Output.SourceCoord = Input.TexCoord;
	Output.SourceCoord += 0.5f / TargetDims;

	Output.Color = Input.Color;

	return Output;
}

//-----------------------------------------------------------------------------
// Scanline & Shadowmask & Distortion Pixel Shader
//-----------------------------------------------------------------------------

uniform float HumBarDesync = 60.0f / 59.94f - 1.0f; // difference between the 59.94 Hz field rate and 60 Hz line frequency (NTSC)
uniform float HumBarAlpha = 0.0f;

uniform float TimeMilliseconds = 0.0f;

uniform float2 ScreenScale = float2(1.0f, 1.0f);
uniform float2 ScreenOffset = float2(0.0f, 0.0f);

uniform float ScanlineAlpha = 0.0f;
uniform float ScanlineScale = 1.0f;
uniform float ScanlineHeight = 1.0f;
uniform float ScanlineVariation = 1.0f;
uniform float ScanlineOffset = 1.0f;
uniform float ScanlineBrightScale = 1.0f;
uniform float ScanlineBrightOffset = 1.0f;

uniform float3 BackColor = float3(0.0f, 0.0f, 0.0f);

uniform int ShadowTileMode = 0; // 0 based on screen (quad) dimension, 1 based on source dimension
uniform float ShadowAlpha = 0.0f;
uniform float2 ShadowCount = float2(6.0f, 6.0f);
uniform float2 ShadowUV = float2(0.25f, 0.25f);

uniform float3 Power = float3(1.0f, 1.0f, 1.0f);
uniform float3 Floor = float3(0.0f, 0.0f, 0.0f);

uniform float CurvatureAmount = 0.0f;
uniform float RoundCornerAmount = 0.0f;
uniform float SmoothBorderAmount = 0.0f;
uniform float VignettingAmount = 0.0f;
uniform float ReflectionAmount = 0.0f;

uniform int RotationType = 0; // 0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°

float2 GetAdjustedCoords(float2 coord, float2 centerOffset)
{
	// center coordinates
	coord -= centerOffset;

	// apply screen scale
	coord /= ScreenScale;

	// un-center coordinates
	coord += centerOffset;

	// apply screen offset
	coord += (centerOffset * 2.0) * ScreenOffset;

	return coord;
}

// vector screen has the same quad texture coordinates for every screen orientation, raster screen differs
float2 GetShadowCoord(float2 QuadCoord, float2 SourceCoord)
{
	float2 QuadTexel = 1.0f / QuadDims;
	float2 SourceTexel = 1.0f / SourceDims;

	float2 canvasCoord = ShadowTileMode == 0
		? QuadCoord + ShadowUVOffset / QuadDims
		: SourceCoord + ShadowUVOffset / SourceDims;
	float2 canvasTexelDims = ShadowTileMode == 0
		? QuadTexel
		: SourceTexel;

	float2 shadowDims = ShadowDims;
	float2 shadowUV = ShadowUV;
	float2 shadowCount = ShadowCount;

	// swap x/y vector and raster in screen mode (not source mode)
	canvasCoord = ShadowTileMode == 0 && SwapXY
		? canvasCoord.yx
		: canvasCoord.xy;

	// swap x/y vector and raster in screen mode (not source mode)
	shadowCount = ShadowTileMode == 0 && SwapXY
		? shadowCount.yx
		: shadowCount.xy;

	float2 shadowTile = canvasTexelDims * shadowCount;

	// swap x/y vector in screen mode (not raster and not source mode)
	shadowTile = VectorScreen && ShadowTileMode == 0 && SwapXY
		? shadowTile.yx
		: shadowTile.xy;

	float2 shadowFrac = frac(canvasCoord / shadowTile);

	// swap x/y raster in screen mode (not vector and not source mode)
	shadowFrac = !VectorScreen && ShadowTileMode == 0 && SwapXY
		? shadowFrac.yx
		: shadowFrac.xy;

	float2 shadowCoord = (shadowFrac * shadowUV);
	shadowCoord += 0.5f / shadowDims; // half texel offset

	return shadowCoord;
}

float GetNoiseFactor(float3 n, float random)
{
	// smaller n become more noisy
	return 1.0f + random * max(0.0f, 0.25f * pow(E, -8 * n));
}

float GetVignetteFactor(float2 coord, float amount)
{
	float2 VignetteCoord = coord;

	float VignetteLength = length(VignetteCoord);
	float VignetteBlur = (amount * 0.75f) + 0.25;

	// 0.5 full screen fitting circle
	float VignetteRadius = 1.0f - (amount * 0.25f);
	float Vignette = smoothstep(VignetteRadius, VignetteRadius - VignetteBlur, VignetteLength);

	return saturate(Vignette);
}

float GetSpotAddend(float2 coord, float amount)
{
	float2 SpotCoord = coord;

	// hack for vector screen
	if (VectorScreen)
	{
		// upper right quadrant
		float2 spotOffset =
			RotationType == 1 // 90°
				? float2(-0.25f, -0.25f)
				: RotationType == 2 // 180°
					? float2(0.25f, -0.25f)
					: RotationType == 3 // 270° else 0°
						? float2(0.25f, 0.25f)
						: float2(-0.25f, 0.25f);

		// normalized screen canvas ratio
		float2 CanvasRatio = SwapXY
			? float2(QuadDims.x / QuadDims.y, 1.0f)
			: float2(1.0f, QuadDims.y / QuadDims.x);

		SpotCoord += spotOffset;
		SpotCoord *= CanvasRatio;
	}
	else
	{
		// upper right quadrant
		float2 spotOffset = float2(-0.25f, 0.25f);

		// normalized screen canvas ratio
		float2 CanvasRatio = SwapXY 
			? float2(1.0f, QuadDims.x / QuadDims.y)
			: float2(1.0f, QuadDims.y / QuadDims.x);

		SpotCoord += spotOffset;
		SpotCoord *= CanvasRatio;
	}

	float SpotBlur = amount;

	// 0.5 full screen fitting circle
	float SpotRadius = amount * 0.75f;
	float Spot = smoothstep(SpotRadius, SpotRadius - SpotBlur, length(SpotCoord));

	float SigmoidSpot = amount * normalizedSigmoid(Spot, 0.75);

	// increase strength by 100%
	SigmoidSpot = SigmoidSpot * 2.0f;

	return saturate(SigmoidSpot);
}

float GetRoundCornerFactor(float2 coord, float radiusAmount, float smoothAmount)
{
	// reduce smooth amount down to radius amount
	smoothAmount = min(smoothAmount, radiusAmount);

	float2 quadDims = QuadDims;
	quadDims = !VectorScreen && SwapXY
		? quadDims.yx
		: quadDims.xy;

	float range = min(quadDims.x, quadDims.y) * 0.5;
	float radius = range * max(radiusAmount, 0.0025f);
	float smooth = 1.0 / (range * max(smoothAmount, 0.0025f));

	// compute box
	float box = roundBox(quadDims * (coord * 2.0f), quadDims, radius);

	// apply smooth
	box *= smooth;
	box += 1.0f - pow(smooth * 0.5f, 0.5f);

	float border = smoothstep(1.0f, 0.0f, box);

	return saturate(border);
}

// www.francois-tarlier.com/blog/cubic-lens-distortion-shader/
float2 GetDistortedCoords(float2 centerCoord, float amount)
{
	// lens distortion coefficient
	float k = amount;

	// cubic distortion value
	float kcube = amount * 2.0f;

	// compute cubic distortion factor
	float r2 = centerCoord.x * centerCoord.x + centerCoord.y * centerCoord.y;
	float f = kcube == 0.0f
		? 1.0f + r2 * k
		: 1.0f + r2 * (k + kcube * sqrt(r2));

   	// fit screen bounds
	f /= 1.0f + amount * 0.5f;

	// apply cubic distortion factor
   	centerCoord *= f;

	return centerCoord;
}

float2 GetCoords(float2 coord, float distortionAmount)
{
	// center coordinates
	coord -= 0.5f;

	// distort coordinates
	coord = GetDistortedCoords(coord, distortionAmount);

	// un-center coordinates
	coord += 0.5f;

	return coord;
}

float4 ps_main(PS_INPUT Input) : COLOR
{
	float2 ScreenCoord = Input.ScreenCoord;
	//float2 TexCoord = GetAdjustedCoords(Input.TexCoord, 0.5f);
	//float2 SourceCoord = GetAdjustedCoords(Input.SourceCoord, 0.5f);
	float2 SourceCoord = GetCoords(Input.SourceCoord, CurvatureAmount * 0.25f); // reduced amount

	// Screen Curvature
	float2 TexCoord = GetCoords(Input.TexCoord, CurvatureAmount * 0.25f); // reduced amount

	float2 TexCoordCentered = TexCoord;
	TexCoordCentered -= 0.5f;

	// Color
	float4 BaseColor = tex2D(DiffuseSampler, TexCoord);
	BaseColor.a = 1.0f;

	// Vignetting Simulation
	if (VignettingAmount > 0.0f)
	{
		float2 VignetteCoord = TexCoordCentered;
		float VignetteFactor = GetVignetteFactor(VignetteCoord, VignettingAmount);
		BaseColor.rgb *= VignetteFactor;
	}

	// Light Reflection Simulation
	if (ReflectionAmount > 0.0f)
	{
		float3 LightColor = float3(1.0f, 0.90f, 0.80f); // color temperature 5.000 Kelvin

		float2 SpotCoord = TexCoordCentered;
		float2 NoiseCoord = TexCoordCentered;

		float SpotAddend = GetSpotAddend(SpotCoord, ReflectionAmount);
		float NoiseFactor = GetNoiseFactor(SpotAddend, random(NoiseCoord));
		BaseColor.rgb += SpotAddend * NoiseFactor * LightColor;
	}

	// Round Corners Simulation
	if (RoundCornerAmount > 0.0f || SmoothBorderAmount > 0.0f)
	{
		float2 RoundCornerCoord = TexCoordCentered;

		float roundCornerFactor = GetRoundCornerFactor(RoundCornerCoord, RoundCornerAmount, SmoothBorderAmount);
		BaseColor.rgb *= roundCornerFactor;
	}

	// keep border
	if (!PrepareBloom)
	{
		// clip border
		clip(TexCoord < 0.0f || TexCoord > 1.0f ? -1 : 1);
	}

	// Mask Simulation (may not affect bloom)
	if (!PrepareBloom && ShadowAlpha > 0.0f)
	{
		float2 ShadowCoord = GetShadowCoord(ScreenCoord, SourceCoord);

		float4 ShadowColor = tex2D(ShadowSampler, ShadowCoord);
		float3 ShadowMaskColor = lerp(1.0f, ShadowColor.rgb, ShadowAlpha);
		float ShadowMaskClear = (1.0f - ShadowColor.a) * ShadowAlpha;

		// apply shadow mask color
		BaseColor.rgb *= ShadowMaskColor;
		// clear shadow mask by background color
		BaseColor.rgb = lerp(BaseColor.rgb, BackColor, ShadowMaskClear);
	}

#if 0
	// Color Compression (may not affect bloom)
	if (!PrepareBloom)
	{
		// increasing the floor of the signal without affecting the ceiling
		BaseColor.rgb = Floor + (1.0f - Floor) * BaseColor.rgb;
	}

	// Color Power (may affect bloom)
	BaseColor.r = pow(BaseColor.r, Power.r);
	BaseColor.g = pow(BaseColor.g, Power.g);
	BaseColor.b = pow(BaseColor.b, Power.b);
#endif

	// Scanline Simulation (may not affect bloom)
	if (!PrepareBloom)
	{
		// Scanline Simulation (may not affect vector screen)
		if (!VectorScreen && ScanlineAlpha > 0.0f)
		{
			float BrightnessOffset = (ScanlineBrightOffset * ScanlineAlpha);
			float BrightnessScale = (ScanlineBrightScale * ScanlineAlpha) + (1.0f - ScanlineAlpha);

			float ColorBrightness = 0.299f * BaseColor.r + 0.587f * BaseColor.g + 0.114 * BaseColor.b;

			float ScanlineCoord = SourceCoord.y * SourceDims.y * ScanlineScale * PI;
			float ScanlineCoordJitter = ScanlineOffset * PHI;
			float ScanlineSine = sin(ScanlineCoord + ScanlineCoordJitter);
			float ScanlineWide = ScanlineHeight + ScanlineVariation * max(1.0f, ScanlineHeight) * (1.0f - ColorBrightness);
			float ScanlineAmount = pow(ScanlineSine * ScanlineSine, ScanlineWide);
			float ScanlineBrightness = ScanlineAmount * BrightnessScale + BrightnessOffset * BrightnessScale;

			BaseColor.rgb *= lerp(1.0f, ScanlineBrightness, ScanlineAlpha);
		}

		// Hum Bar Simulation (may not affect vector screen)
		if (!VectorScreen && HumBarAlpha > 0.0f)
		{
			float HumBarStep = frac(TimeMilliseconds * HumBarDesync);
			float HumBarBrightness = 1.0 - frac(SourceCoord.y + HumBarStep) * HumBarAlpha;
			BaseColor.rgb *= HumBarBrightness;
		}
	}

	return BaseColor;
}

//-----------------------------------------------------------------------------
// Scanline & Shadowmask & Distortion Technique
//-----------------------------------------------------------------------------

technique DefaultTechnique
{
	pass Pass0
	{
		Lighting = FALSE;

		VertexShader = compile vs_3_0 vs_main();
		PixelShader = compile ps_3_0 ps_main();
	}
}