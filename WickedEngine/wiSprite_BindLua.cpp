#include "wiSprite_BindLua.h"
#include "wiImageParams_BindLua.h"
#include "wiSpriteAnim_BindLua.h"

namespace wi::lua
{

	const char Sprite_BindLua::className[] = "Sprite";

	Luna<Sprite_BindLua>::FunctionType Sprite_BindLua::methods[] = {
		lunamethod(Sprite_BindLua, SetParams),
		lunamethod(Sprite_BindLua, GetParams),
		lunamethod(Sprite_BindLua, SetAnim),
		lunamethod(Sprite_BindLua, GetAnim),

		{ NULL, NULL }
	};
	Luna<Sprite_BindLua>::PropertyType Sprite_BindLua::properties[] = {
		{ NULL, NULL }
	};

	Sprite_BindLua::Sprite_BindLua(const wi::Sprite& sprite) :sprite(sprite)
	{
	}

	Sprite_BindLua::Sprite_BindLua(lua_State* L)
	{
		std::string name = "", mask = "";
		int argc = wi::lua::SGetArgCount(L);
		if (argc > 0)
		{
			name = wi::lua::SGetString(L, 1);
			if (argc > 1)
			{
				mask = wi::lua::SGetString(L, 2);
			}
		}
		sprite = wi::Sprite(name, mask);
	}

	int Sprite_BindLua::SetParams(lua_State* L)
	{
		int argc = wi::lua::SGetArgCount(L);
		if (argc > 0)
		{
			wi::lua::ImageParams_BindLua* params = Luna<wi::lua::ImageParams_BindLua>::check(L, 1);
			if (params != nullptr)
			{
				sprite.params = params->params;
			}
		}
		else
		{
			wi::lua::SError(L, "SetParams(ImageEffects effects) not enough arguments!");
		}
		return 0;
	}
	int Sprite_BindLua::GetParams(lua_State* L)
	{
		Luna<wi::lua::ImageParams_BindLua>::push(L, new wi::lua::ImageParams_BindLua(sprite.params));
		return 1;
	}
	int Sprite_BindLua::SetAnim(lua_State* L)
	{
		int argc = wi::lua::SGetArgCount(L);
		if (argc > 0)
		{
			SpriteAnim_BindLua* anim = Luna<SpriteAnim_BindLua>::check(L, 1);
			if (anim != nullptr)
			{
				sprite.anim = anim->anim;
			}
		}
		else
		{
			wi::lua::SError(L, "SetAnim(SpriteAnim anim) not enough arguments!");
		}
		return 0;
	}
	int Sprite_BindLua::GetAnim(lua_State* L)
	{
		Luna<SpriteAnim_BindLua>::push(L, new SpriteAnim_BindLua(sprite.anim));
		return 1;
	}

	void Sprite_BindLua::Bind()
	{
		static bool initialized = false;
		if (!initialized)
		{
			initialized = true;
			Luna<Sprite_BindLua>::Register(wi::lua::GetLuaState());
		}
	}

}
