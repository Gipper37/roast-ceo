-- sorted_onboarding_slides view
-- AppSheet's Onboarding view has no Sort By option. This view bakes in
-- ORDER BY sort_order so AppSheet always receives rows in the correct sequence.

CREATE VIEW sorted_onboarding_slides AS
SELECT * FROM onboarding_slides ORDER BY sort_order ASC;
