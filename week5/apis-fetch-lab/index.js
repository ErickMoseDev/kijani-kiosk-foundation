const abbrInput = document.querySelector('#state-input');
const btn = document.querySelector('#fetch-alerts');
const alertsDisplay = document.querySelector('#alerts-display');
const errorSection = document.querySelector('#error-message');

btn.addEventListener('click', () => {
	const state = abbrInput.value;

	displayAlerts(state);

	// reset the form
	abbrInput.value = '';
});

function displayAlerts(state) {
	fetch(`https://api.weather.gov/alerts/active?area=${state}`)
		.then((res) => res.json())
		.then((data) => {
			console.log(data);
			const title = document.createElement('h2');
			const list = document.createElement('ul');

			// display info
			if (data) {
				const len = data.features.length;
				const features = data.features;
				title.innerHTML = `${data.title}: ${len}`;
				alertsDisplay.append(title);
				features.forEach((feature) => {
					const li = document.createElement('li');
					li.textContent = feature.properties.headline;
					list.append(li);
				});

				// add features
				alertsDisplay.append(list);
			}

			errorSection.innerHTML = '';
			errorSection.classList.add('hidden');
		})
		.catch((error) => {
			errorSection.classList.remove('hidden');
			errorSection.append(error.message);
		});
}
