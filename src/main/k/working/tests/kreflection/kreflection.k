require "substitution.k"

module KREFLECTION
  imports K-REFLECTION-SYMBOLIC
  imports K-REFLECTION
  imports DOMAINS
  imports SUBSTITUTION

  syntax Val ::= "concrete"

  rule concrete => #isConcrete(#configuration)

endmodule
