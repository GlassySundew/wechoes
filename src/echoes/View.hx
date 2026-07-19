package echoes;

import echoes.Query.DynamicQuery;
import echoes.Query.QueryBase;

/**
 * Compatibility names for the former View API. New code should use
 * `echoes.Query`.
 */
#if !macro
@:deprecated( "Use echoes.Query instead." )
@:genericBuild( echoes.macro.ViewBuilder.build() )
#end
abstract class View<Rest> extends QueryBase {}

@:deprecated( "Use echoes.Query.QueryBase instead." )
typedef ViewBase = QueryBase;

@:deprecated( "Use echoes.Query.DynamicQuery instead." )
typedef DynamicView = DynamicQuery;
