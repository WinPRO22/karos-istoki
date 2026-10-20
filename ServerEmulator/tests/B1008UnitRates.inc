// Deterministic rewards must not depend on the player's live rates-v1.ini.
function FixtureRates:TB1008Rates;
begin
  Result.Drop:=B1008RateOne;Result.Experience:=B1008RateOne;
  Result.Fletta:=B1008RateOne;Result.Carat:=B1008RateOne;
end;
