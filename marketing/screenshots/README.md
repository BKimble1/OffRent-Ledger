# Marketing screenshots

Empty on purpose. The app has not been launched yet, so no screenshot of it exists.

The website renders a labelled reserved frame for each of the captures below, naming the exact
file it is waiting for. To fill them:

1. Run the app on an iPhone simulator or a device.
2. Capture these screens, portrait, at native resolution (1290×2796 for an iPhone 16 Pro):

   | File                 | Screen                                                     |
   |----------------------|------------------------------------------------------------|
   | `today.png`          | Today, with two or three rentals accruing                   |
   | `rentals.png`        | Rentals list, mixed statuses                                |
   | `rental-detail.png`  | One rental with terms, running estimate and timeline        |
   | `scan-review.png`    | Scan review, values ticked and unticked                     |
   | `confirmation.png`   | Vendor confirmation recorded                                |
   | `awaiting-pickup.png`| Awaiting pickup                                             |
   | `invoice-review.png` | Invoice review showing a possible mismatch                  |

3. Drop them here, add them to `SCREENSHOTS` in `scripts/generate_website.py` with their real
   pixel dimensions and alt text, then re-run the generator and the packager.

Use the walkthrough fixture (`-offrent-seed-walkthrough`) so the figures are the ones the tests
and the documentation already use. Do not retouch the numbers.
