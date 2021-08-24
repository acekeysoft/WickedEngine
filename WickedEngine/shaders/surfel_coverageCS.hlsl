#include "globals.hlsli"
#include "ShaderInterop_SurfelGI.h"
#include "brdf.hlsli"

//#define SURFEL_DEBUG_NORMAL
//#define SURFEL_DEBUG_COLOR
//#define SURFEL_DEBUG_POINT
//#define SURFEL_DEBUG_RANDOM
#define SURFEL_DEBUG_HEATMAP


static const uint random_colors_size = 11;
static const float3 random_colors[random_colors_size] = {
	float3(0,0,1),
	float3(0,1,1),
	float3(0,1,0),
	float3(1,1,0),
	float3(1,0,0),
	float3(1,0,1),
	float3(0.5,1,1),
	float3(0.5,1,0.5),
	float3(1,1,0.5),
	float3(1,0.5,0.5),
	float3(1,0.5,1),
};
float3 random_color(uint index)
{
	return random_colors[index % random_colors_size];
}

STRUCTUREDBUFFER(surfelBuffer, Surfel, TEXSLOT_ONDEMAND0);
STRUCTUREDBUFFER(surfelGridBuffer, SurfelGridCell, TEXSLOT_ONDEMAND2);
STRUCTUREDBUFFER(surfelCellBuffer, uint, TEXSLOT_ONDEMAND3);

RWSTRUCTUREDBUFFER(surfelDataBuffer, SurfelData, 0);
RWRAWBUFFER(surfelStatsBuffer, 1);
RWTEXTURE2D(result, float3, 2);
RWTEXTURE2D(debugUAV, unorm float4, 3);

groupshared uint GroupMinSurfelCount;

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint groupIndex : SV_GroupIndex, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
	if (groupIndex == 0)
	{
		GroupMinSurfelCount = ~0;
	}
	GroupMemoryBarrierWithGroupSync();

	uint2 pixel = DTid.xy;

	const float depth = texture_depth[pixel];
	if (depth == 0)
	{
		debugUAV[pixel] = 0;
		return;
	}

	float4 debug = 0;
	float4 color = 0;

	const float2 uv = ((float2)pixel + 0.5) * g_xFrame_InternalResolution_rcp;
	const float3 P = reconstructPosition(uv, depth);

	uint2 primitiveID = texture_gbuffer0[pixel];

	PrimitiveID prim;
	prim.unpack(primitiveID);

	Surface surface;
	if (!surface.load(prim, P))
	{
		return;
	}

	const float3 N = surface.facenormal;

	float coverage = 0;

	uint cellindex = surfel_cellindex(surfel_cell(P));
	SurfelGridCell cell = surfelGridBuffer[cellindex];
	for (uint i = 0; i < cell.count; ++i)
	{
		uint surfel_index = surfelCellBuffer[cell.offset + i];
		Surfel surfel = surfelBuffer[surfel_index];

		float3 L = surfel.position - P;
		float dist2 = dot(L, L);
		if (dist2 < sqr(surfel.radius))
		{
			float3 normal = normalize(unpack_unitvector(surfel.normal));
			float dotN = dot(N, normal);
			if (dotN > 0)
			{
				float dist = sqrt(dist2);
				float contribution = 1;
				contribution *= pow(saturate(dotN), SURFEL_NORMAL_TOLERANCE);
				contribution *= saturate(1 - dist / surfel.radius);
				contribution = smoothstep(0, 1, contribution);
				coverage += contribution;

				color += float4(surfel.color, 1) * contribution;

#ifdef SURFEL_DEBUG_NORMAL
				debug.rgb += normal * contribution;
				debug.a = 1;
#endif // SURFEL_DEBUG_NORMAL

#ifdef SURFEL_DEBUG_RANDOM
				debug += float4(random_color(surfel_index), 1) * contribution;
#endif // SURFEL_DEBUG_RANDOM

			}

#ifdef SURFEL_DEBUG_POINT
			if (dist2 <= sqr(0.05))
				debug = float4(1, 0, 1, 1);
#endif // SURFEL_DEBUG_POINT
		}

	}

	if (cell.count < SURFEL_CELL_LIMIT)
	{
		uint surfel_count_at_pixel = 0;
		surfel_count_at_pixel |= (uint(coverage) & 0xFF) << 8;
		surfel_count_at_pixel |= (GTid.x & 0xF) << 4;
		surfel_count_at_pixel |= (GTid.y & 0xF) << 0;
		InterlockedMin(GroupMinSurfelCount, surfel_count_at_pixel);
	}

	if (color.a > 0)
	{
		color.rgb /= color.a;
		color.a = saturate(color.a);
	}
	else
	{
		color = 0;
	}

#ifdef SURFEL_DEBUG_NORMAL
	debug.rgb = normalize(debug.rgb) * 0.5 + 0.5;
#endif // SURFEL_DEBUG_NORMAL

#ifdef SURFEL_DEBUG_COLOR
	debug = color;
	debug.rgb = tonemap(debug.rgb);
#endif // SURFEL_DEBUG_COLOR

#if defined(SURFEL_DEBUG_RANDOM)
	if (debug.a > 0)
	{
		debug /= debug.a;
	}
	else
	{
		debug = 0;
	}
#endif // SURFEL_DEBUG_RANDOM

#ifdef SURFEL_DEBUG_HEATMAP
	const float3 mapTex[] = {
		float3(0,0,0),
		float3(0,0,1),
		float3(0,1,1),
		float3(0,1,0),
		float3(1,1,0),
		float3(1,0,0),
	};
	const uint mapTexLen = 5;
	const uint maxHeat = 50;
	float l = saturate((float)cell.count / maxHeat) * mapTexLen;
	float3 a = mapTex[floor(l)];
	float3 b = mapTex[ceil(l)];
	float4 heatmap = float4(lerp(a, b, l - floor(l)), 0.8);
	debug = heatmap;
#endif // SURFEL_DEBUG_HEATMAP


	GroupMemoryBarrierWithGroupSync();

	uint surfel_coverage = GroupMinSurfelCount;
	uint2 minGTid;
	minGTid.x = (surfel_coverage >> 4) & 0xF;
	minGTid.y = (surfel_coverage >> 0) & 0xF;
	uint coverage_amount = surfel_coverage >> 8;
	if (GTid.x == minGTid.x && GTid.y == minGTid.y && coverage_amount < SURFEL_TARGET_COVERAGE)
	{
		// Slow down the propagation by chance
		//	Closer surfaces have less chance to avoid excessive clumping of surfels
		const float lineardepth = getLinearDepth(depth) * g_xCamera_ZFarP_rcp;
		const float chance = pow(1 - lineardepth, 4);
		if (blue_noise(Gid.xy).x < chance)
			return;

		uint surfel_alloc;
		surfelStatsBuffer.InterlockedAdd(SURFEL_STATS_OFFSET_COUNT, 1, surfel_alloc);
		if (surfel_alloc < SURFEL_CAPACITY)
		{
			SurfelData surfel_data = (SurfelData)0;
			surfel_data.primitiveID = primitiveID;
			surfel_data.bary = pack_half2(surface.bary.xy);
			surfel_data.uid = surface.inst.uid;
			surfel_data.inconsistency = 1;
			surfelDataBuffer[surfel_alloc] = surfel_data;
		}
	}

	result[pixel] = color.rgb;
	debugUAV[pixel] = debug;
}
