import { createElement } from "lwc";
import DeepClone from "c/deepClone";
import getConfig from "@salesforce/apex/RecordCloneController.getConfig";
import doClone from "@salesforce/apex/RecordCloneController.doClone";

// Wired Apex method mock (emittable test wire adapter).
jest.mock(
  "@salesforce/apex/RecordCloneController.getConfig",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// Imperative Apex method mock.
jest.mock(
  "@salesforce/apex/RecordCloneController.doClone",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const RECORD_ID = "001000000000001AAA";

const ENABLED_CONFIG = {
  objectApiName: "Account",
  deepCloneEnabled: true,
  childRelationshipNames: ["Contacts"],
  excludedFields: ["Website"],
  namePrefix: "Copy of "
};

function createComponent() {
  const element = createElement("c-deep-clone", { is: DeepClone });
  element.recordId = RECORD_ID;
  element.objectApiName = "Account";
  document.body.appendChild(element);
  return element;
}

async function flushPromises() {
  return Promise.resolve();
}

describe("c-deep-clone", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a loading spinner until the configuration resolves", () => {
    const element = createComponent();

    const spinner = element.shadowRoot.querySelector("lightning-spinner");
    expect(spinner).not.toBeNull();
  });

  it("renders the clone button and child summary when deep clone is enabled", async () => {
    const element = createComponent();

    getConfig.emit(ENABLED_CONFIG);
    await flushPromises();

    const button = element.shadowRoot.querySelector("lightning-button");
    expect(button).not.toBeNull();
    expect(element.shadowRoot.textContent).toContain("Contacts");
    expect(element.shadowRoot.textContent).toContain("Website");
  });

  it("invokes doClone with the record id when the button is clicked", async () => {
    doClone.mockResolvedValue("001000000000999AAA");
    const element = createComponent();

    getConfig.emit(ENABLED_CONFIG);
    await flushPromises();

    const button = element.shadowRoot.querySelector("lightning-button");
    button.dispatchEvent(new CustomEvent("click"));
    await flushPromises();
    await flushPromises();

    expect(doClone).toHaveBeenCalledWith({ recordId: RECORD_ID });
  });
});
