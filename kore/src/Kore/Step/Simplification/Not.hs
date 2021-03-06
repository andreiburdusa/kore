{-|
Module      : Kore.Step.Simplification.Not
Description : Tools for Not pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Not
    ( makeEvaluate
    , makeEvaluatePredicate
    , simplify
    , simplifyEvaluated
    , simplifyEvaluatedPredicate
    , notSimplifier
    ) where

import Prelude.Kore

import Kore.Internal.Condition
    ( Condition
    )
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional
import Kore.Internal.MultiAnd
    ( MultiAnd
    )
import qualified Kore.Internal.MultiAnd as MultiAnd
import Kore.Internal.MultiOr
    ( MultiOr
    )
import qualified Kore.Internal.MultiOr as MultiOr
import Kore.Internal.OrCondition
    ( OrCondition
    )
import qualified Kore.Internal.OrCondition as OrCondition
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeAndPredicate
    , makeNotPredicate
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.SideCondition
    ( SideCondition
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
import qualified Kore.Internal.TermLike as TermLike
    ( markSimplified
    )
import qualified Kore.Step.Simplification.And as And
import Kore.Step.Simplification.NotSimplifier
import Kore.Step.Simplification.Simplify
import Kore.TopBottom
    ( TopBottom (..)
    )
import Logic

{-|'simplify' simplifies a 'Not' pattern with an 'OrPattern'
child.

Right now this uses the following:

* not top = bottom
* not bottom = top

-}
simplify
    :: (InternalVariable variable, MonadSimplify simplifier)
    => SideCondition variable
    -> Not Sort (OrPattern variable)
    -> simplifier (OrPattern variable)
simplify sideCondition Not { notChild } =
    simplifyEvaluated sideCondition notChild

{-|'simplifyEvaluated' simplifies a 'Not' pattern given its
'OrPattern' child.

See 'simplify' for details.
-}
{- TODO (virgil): Preserve pattern sorts under simplification.

One way to preserve the required sort annotations is to make 'simplifyEvaluated'
take an argument of type

> CofreeF (Not Sort) (Attribute.Pattern variable) (OrPattern variable)

instead of an 'OrPattern' argument. The type of 'makeEvaluate' may
be changed analogously. The 'Attribute.Pattern' annotation will eventually
cache information besides the pattern sort, which will make it even more useful
to carry around.

-}
simplifyEvaluated
    :: (InternalVariable variable, MonadSimplify simplifier)
    => SideCondition variable
    -> OrPattern variable
    -> simplifier (OrPattern variable)
simplifyEvaluated sideCondition simplified =
    OrPattern.observeAllT $ do
        let not' = Not { notChild = simplified, notSort = () }
        andPattern <-
            scatterAnd (MultiAnd.map makeEvaluateNot (distributeNot not'))
        mkMultiAndPattern sideCondition andPattern

simplifyEvaluatedPredicate
    :: (InternalVariable variable, MonadSimplify simplifier)
    => OrCondition variable
    -> simplifier (OrCondition variable)
simplifyEvaluatedPredicate notChild =
    OrCondition.observeAllT $ do
        let not' = Not { notChild = notChild, notSort = () }
        andPredicate <-
            scatterAnd
                ( MultiAnd.map
                    makeEvaluateNotPredicate
                    (distributeNot not')
                )
        mkMultiAndPredicate andPredicate

{-|'makeEvaluate' simplifies a 'Not' pattern given its 'Pattern'
child.

See 'simplify' for details.
-}
makeEvaluate
    :: InternalVariable variable
    => Pattern variable
    -> OrPattern variable
makeEvaluate = makeEvaluateNot . Not ()

makeEvaluateNot
    :: InternalVariable variable
    => Not sort (Pattern variable)
    -> OrPattern variable
makeEvaluateNot Not { notChild } =
    MultiOr.merge
        (MultiOr.map Pattern.fromTermLike $ makeTermNot term)
        (makeEvaluatePredicate condition
            & Pattern.fromCondition (termLikeSort term)
            & MultiOr.singleton
        )
  where
    (term, condition) = Conditional.splitTerm notChild

{- | Given a not's @Internal.Condition@ argument, simplifies the @not@.

Right now there is no actual simplification, this function just creates
a negated @Internal.Condition@.

I.e. if we want to simplify @not (predicate and substitution)@, we may pass
@predicate and substitution@ to this function, which will convert
@predicate and substitution@ into a @Kore.Internal.Predicate@ and will apply
a @not@ on top of that.
-}
makeEvaluatePredicate
    :: InternalVariable variable
    => Condition variable
    -> Condition variable
makeEvaluatePredicate
    Conditional
        { term = ()
        , predicate
        , substitution
        }
  = Conditional
        { term = ()
        , predicate =
            Predicate.markSimplified
            $ makeNotPredicate
            $ makeAndPredicate predicate
            $ Substitution.toPredicate substitution
        , substitution = mempty
        }

makeEvaluateNotPredicate
    :: InternalVariable variable
    => Not sort (Condition variable)
    -> OrCondition variable
makeEvaluateNotPredicate Not { notChild = predicate } =
    OrCondition.fromConditions [ makeEvaluatePredicate predicate ]

makeTermNot
    :: InternalVariable variable
    => TermLike variable
    -> MultiOr (TermLike variable)
-- TODO: maybe other simplifications like
-- not ceil = floor not
-- not forall = exists not
makeTermNot (Not_ _ term) = MultiOr.singleton term
makeTermNot (And_ _ term1 term2) =
    MultiOr.merge (makeTermNot term1) (makeTermNot term2)
makeTermNot term
  | isBottom term = MultiOr.singleton mkTop_
  | isTop term    = MultiOr.singleton mkBottom_
  | otherwise     = MultiOr.singleton $ TermLike.markSimplified $ mkNot term

{- | Distribute 'Not' over 'MultiOr' using de Morgan's identity.
 -}
distributeNot
    :: (Ord sort, Ord child, TopBottom child)
    => Not sort (MultiOr child)
    -> MultiAnd (Not sort child)
distributeNot notOr@Not { notChild } =
    MultiAnd.make $ worker <$> toList notChild
  where
    worker child = notOr { notChild = child }

{- | Distribute 'MultiAnd' over 'MultiOr' and 'scatter' into 'LogicT'.
 -}
scatterAnd
    :: Ord child
    => TopBottom child
    => MultiAnd (MultiOr child)
    -> LogicT m (MultiAnd child)
scatterAnd = scatter . MultiOr.distributeAnd

{- | Conjoin and simplify a 'MultiAnd' of 'Pattern'.
 -}
mkMultiAndPattern
    :: (InternalVariable variable, MonadSimplify simplifier)
    => SideCondition variable
    -> MultiAnd (Pattern variable)
    -> LogicT simplifier (Pattern variable)
mkMultiAndPattern = And.makeEvaluate notSimplifier

{- | Conjoin and simplify a 'MultiAnd' of 'Condition'.
 -}
mkMultiAndPredicate
    :: InternalVariable variable
    => MultiAnd (Condition variable)
    -> LogicT simplifier (Condition variable)
mkMultiAndPredicate predicates =
    -- Using fold because the Monoid instance of Condition
    -- implements And semantics.
    return $ fold predicates

notSimplifier
    :: MonadSimplify simplifier
    => NotSimplifier simplifier
notSimplifier =
    NotSimplifier simplifyEvaluated
